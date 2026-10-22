import SwiftUI
import SwiftData

struct CategoryManagementView: View {
    @Query(sort: \Category.name) private var categories: [Category]
    @State private var selected: Category?
    @State private var adding = false
    var body: some View {
        List {
            Section {
                ForEach(categories) { category in
                    Button { selected = category } label: {
                        HStack {
                            SymbolTile(symbol: category.symbol, tint: category.color)
                            Text(category.name).foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                        }.padding(.vertical, 3)
                    }
                }
            } footer: { Text("Personalize símbolos e cores ou crie categorias para organizar seus lançamentos.") }
        }
        .navigationTitle("Categorias").navigationBarTitleDisplayMode(.inline)
        .toolbar { Button("Nova categoria", systemImage: "plus") { adding = true } }
        .sheet(isPresented: $adding) { CategoryForm() }
        .sheet(item: $selected) { CategoryForm(category: $0) }
    }
}

private struct CategoryForm: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    var category: Category? = nil
    @State private var name = ""
    @State private var symbol = "tag.fill"
    @State private var color = "teal"
    @State private var error: String?
    private let symbols = ["tag.fill", "cart.fill", "fork.knife", "house.fill", "car.fill", "heart.fill", "book.fill", "airplane", "gift.fill", "pawprint.fill", "sportscourt.fill", "briefcase.fill", "banknote.fill", "play.tv.fill"]
    private let colors = ["teal", "blue", "green", "orange", "purple", "pink", "red"]
    private let colorNames = ["teal": "Verde-petróleo", "blue": "Azul", "green": "Verde", "orange": "Laranja", "purple": "Roxo", "pink": "Rosa", "red": "Vermelho"]
    private var isDefault: Bool {
        ["Streaming", "Alimentação", "Moradia", "Transporte", "Saúde", "Lazer", "Educação", "Salário", "Outros"].contains(category?.name ?? "")
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Identificação") { TextField("Nome", text: $name).disabled(isDefault) }
                Section("Símbolo") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))]) {
                        ForEach(symbols, id: \.self) { item in
                            Button { symbol = item } label: {
                                Image(systemName: item).font(.title3).frame(width: 44, height: 44)
                                    .background(symbol == item ? Color.accentColor.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 10))
                            }.buttonStyle(.plain).accessibilityLabel(item).accessibilityAddTraits(symbol == item ? .isSelected : [])
                        }
                    }
                }
                Section("Cor") { Picker("Cor", selection: $color) { ForEach(colors, id: \.self) { Text(colorNames[$0] ?? $0).tag($0) } } }
                if let category, !isDefault, category.transactions.isEmpty, category.subscriptions.isEmpty {
                    Section {
                        Button("Excluir categoria", role: .destructive) {
                            do {
                                for payment in try context.fetch(FetchDescriptor<ScheduledPayment>()) where payment.categoryID == category.id { payment.categoryID = nil }
                                context.delete(category)
                                try context.save(); FinanceEvents.saved(); dismiss()
                            }
                            catch { context.rollback(); self.error = error.localizedDescription }
                        }
                    }
                }
            }
            .navigationTitle(category == nil ? "Nova categoria" : "Editar categoria").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Salvar") { save() }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
            .onAppear { if let category { name = category.name; symbol = category.symbol; color = category.colorName } }
            .financeError($error)
        }
    }
    private func save() {
        do {
            let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let existing = try context.fetch(FetchDescriptor<Category>())
            guard !clean.isEmpty, !existing.contains(where: { $0.id != category?.id && $0.name.localizedCaseInsensitiveCompare(clean) == .orderedSame }) else {
                throw FinanceError.invalid("Escolha um nome diferente para a categoria.")
            }
            if let category { category.name = clean; category.symbol = symbol; category.colorName = color }
            else { context.insert(Category(name: clean, symbol: symbol, colorName: color)) }
            try context.save(); FinanceEvents.saved(); dismiss()
        } catch { context.rollback(); self.error = error.localizedDescription }
    }
}
