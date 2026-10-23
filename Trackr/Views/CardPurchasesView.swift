import SwiftUI
import SwiftData

struct CardPurchaseRow: View {
    let purchase: CardPurchaseGroup
    @AppStorage("trackr.hideAmounts") private var hideAmounts = false
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            SymbolTile(symbol: purchase.category?.symbol ?? "bag", tint: purchase.category?.color ?? TrackrTheme.accent)
            VStack(alignment: .leading, spacing: 5) {
                Text(purchase.title).font(.headline).foregroundStyle(Color.primary)
                Text(purchase.card.name + " • " + purchase.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption).foregroundStyle(.secondary)
                Text(purchase.installments > 1 ? "\(purchase.installments) parcelas • valor total" : (purchase.isRecurring ? "Cobrança recorrente" : "Compra à vista no cartão"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(hideAmounts ? "••••" : Money.format(purchase.amountCents)).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(Color.primary)
        }.padding(.vertical, 5).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            .accessibilityElement(children: .combine)
    }
}

struct CardPurchasesSection: View {
    let card: CreditCard
    let invoice: Invoice?
    @State private var showInvoiceOnly = false
    @State private var selected: CardPurchaseGroup?
    var body: some View {
        Section {
            if invoice != nil {
                Picker("Exibir compras", selection: $showInvoiceOnly) {
                    Text("Todas as compras").tag(false)
                    Text("Nesta fatura").tag(true)
                }.pickerStyle(.segmented)
            }
            if showInvoiceOnly, let invoice {
                ForEach(invoice.lines) { line in
                    if let row = card.transactions.first(where: { $0.id.uuidString == line.id }),
                       let purchase = CardPurchaseService.groups(for: card).first(where: { $0.purchaseID == row.purchaseID }) {
                        Button { selected = purchase } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                MoneyRow(title: line.title, cents: line.amountCents, symbol: "bag")
                                if line.totalInstallments > 1 { Text("Parcela \(line.installmentNumber)/\(line.totalInstallments)").font(.caption).foregroundStyle(.secondary) }
                            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    } else {
                        VStack(alignment: .leading, spacing: 5) {
                            MoneyRow(title: line.title, cents: line.amountCents, symbol: "clock.arrow.circlepath")
                            Text("Previsão de recorrência").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                let purchases = CardPurchaseService.groups(for: card)
                if purchases.isEmpty { Text("Nenhuma compra registrada.").foregroundStyle(.secondary) }
                ForEach(purchases) { purchase in
                    Button { selected = purchase } label: { CardPurchaseRow(purchase: purchase) }.buttonStyle(.plain)
                }
            }
        } header: { Text("Compras no cartão") } footer: {
            Text("Toque para ver parcelas e opções de exclusão. Em compras parceladas, a exclusão remove a compra inteira. Previsões de recorrências são gerenciadas em Pagamentos.")
        }
        .sheet(item: $selected) { CardPurchaseDetailView(card: $0.card, purchaseID: $0.purchaseID) }
    }
}

struct CardPurchaseDetailView: View {
    let card: CreditCard
    let purchaseID: UUID
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var confirming = false
    @State private var error: String?
    private var purchase: CardPurchaseGroup? { CardPurchaseService.groups(for: card).first { $0.purchaseID == purchaseID } }
    var body: some View {
        NavigationStack {
            List {
                if let purchase {
                    Section {
                        Text(purchase.title).font(.title2.weight(.semibold))
                        MoneyRow(title: "Valor total", cents: purchase.amountCents, symbol: "bag")
                        LabeledContent("Cartão", value: card.name)
                        LabeledContent("Compra", value: purchase.date.formatted(date: .abbreviated, time: .omitted))
                        CategoryLabel(category: purchase.category)
                    }
                    Section("Parcelas por vencimento") {
                        ForEach(purchase.transactions) { transaction in
                            VStack(alignment: .leading, spacing: 5) {
                                MoneyRow(title: "\(transaction.installmentNumber)/\(transaction.totalInstallments)", cents: transaction.amountCents, symbol: "doc.text")
                                if let due = transaction.invoiceDueDate { Text(due.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                    Section {
                        Button("Excluir compra e parcelas", role: .destructive) { confirming = true }.foregroundStyle(.red)
                    } footer: {
                        Text(purchase.hasRecordedPayment ? "Pagamentos que excederem as cobranças restantes da fatura serão preservados como despesas no Extrato. O saldo da conta será mantido." : (purchase.isRecurring ? "A exclusão remove esta cobrança. Para interromper as próximas, pause a recorrência em Pagamentos." : "O limite e as faturas serão recalculados. O saldo da conta só muda com pagamentos de faturas."))
                    }
                } else { ContentUnavailableView("Compra removida", systemImage: "bag") }
            }
            .trackrListScreen("Compra no cartão", largeTitle: false)
            .toolbar { ToolbarItem(placement: .confirmationAction) { TrackrToolbarButton("Concluir", systemImage: "checkmark") { dismiss() } } }
            .confirmationDialog("Excluir esta compra?", isPresented: $confirming, titleVisibility: .visible) {
                Button("Excluir compra e todas as parcelas", role: .destructive) {
                    do { try CreditCardViewModel().deletePurchase(context: context, card: card, purchaseID: purchaseID); dismiss() }
                    catch { self.error = error.localizedDescription }
                }
            } message: { Text("Todas as parcelas registradas desta compra serão removidas do cartão e das faturas. Pagamentos efetivamente realizados serão mantidos no histórico financeiro.") }
            .financeError($error)
        }
    }
}
