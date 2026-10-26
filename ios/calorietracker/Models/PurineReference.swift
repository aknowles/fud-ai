import Foundation

/// Built-in purine reference used as a fallback when neither the AI, the barcode database
/// (Open Food Facts has no purine field) nor USDA FDC (no purine nutrient) supplied a value.
///
/// Values are approximate total purines in mg per 100 g of the food as eaten (per 100 ml for
/// drinks), rounded from commonly cited purine tables (Kaneko et al. 2014, Biol Pharm Bull;
/// the German and Japanese purine tables). They are day-level estimates for gout tracking,
/// not measurements, and match on the food name the same way a person would skim a table.
enum PurineReference {
    struct Food: Sendable, Equatable {
        let name: String
        /// Lowercase match terms; multi-word terms are allowed and the longest match wins.
        let keywords: [String]
        let milligramsPer100g: Double

        init(_ name: String, _ keywords: [String], _ milligramsPer100g: Double) {
            self.name = name
            self.keywords = keywords
            self.milligramsPer100g = milligramsPer100g
        }
    }

    nonisolated static let storageKey = SupplementalNutrient.purines.rawValue

    /// Assumed weight when an entry has no serving size (per-100 g value is used as-is).
    nonisolated static let assumedGrams: Double = 100

    nonisolated static let foods: [Food] = [
        // Organ meats and extracts (high)
        Food("Sweetbreads", ["sweetbreads", "sweetbread", "thymus"], 400),
        Food("Chicken liver", ["chicken liver", "chicken livers"], 310),
        Food("Pork liver", ["pork liver", "pig liver"], 290),
        Food("Beef liver", ["beef liver", "calf liver", "liver"], 220),
        Food("Kidney", ["kidney", "kidneys"], 210),
        Food("Heart", ["beef heart", "chicken heart", "chicken hearts"], 170),
        Food("Pate", ["pate", "pâté", "liverwurst", "foie gras"], 220),
        Food("Tripe", ["tripe"], 80),
        Food("Yeast extract", ["yeast extract", "marmite", "vegemite", "nutritional yeast"], 600),
        Food("Beef jerky", ["beef jerky", "jerky", "biltong"], 200),
        Food("Gravy", ["gravy", "meat extract", "demi glace", "bouillon"], 70),
        Food("Broth", ["bone broth", "beef broth", "chicken broth", "chicken stock", "beef stock", "broth", "stock"], 50),

        // Fish and seafood
        Food("Sardines", ["sardine", "sardines"], 345),
        Food("Anchovies", ["anchovy", "anchovies", "anchovy paste"], 240),
        Food("Herring", ["herring", "kipper", "kippers"], 210),
        Food("Tuna", ["tuna", "ahi", "canned tuna", "tuna salad"], 160),
        Food("Mackerel", ["mackerel"], 145),
        Food("Shrimp", ["shrimp", "prawn", "prawns"], 145),
        Food("Caviar", ["caviar", "roe", "fish roe", "ikura"], 145),
        Food("Haddock", ["haddock"], 140),
        Food("Octopus", ["octopus", "takoyaki"], 140),
        Food("Scallops", ["scallop", "scallops"], 135),
        Food("Clams", ["clam", "clams", "clam chowder"], 135),
        Food("Squid", ["squid", "calamari"], 135),
        Food("Salmon", ["salmon", "smoked salmon", "lox"], 130),
        Food("Trout", ["trout"], 130),
        Food("Halibut", ["halibut"], 130),
        Food("Lobster", ["lobster"], 120),
        Food("Cod", ["cod", "codfish"], 110),
        Food("Sea bass", ["sea bass", "bass", "branzino"], 110),
        Food("Mussels", ["mussel", "mussels"], 110),
        Food("Crab", ["crab", "crab meat", "crab cake", "crab cakes"], 100),
        Food("Oysters", ["oyster", "oysters"], 90),
        Food("Tilapia", ["tilapia"], 90),
        Food("Fish sticks", ["fish sticks", "fish fingers", "fish and chips", "fried fish"], 90),
        Food("Sushi", ["sushi", "sashimi", "poke bowl", "poke"], 60),

        // Meat and poultry
        Food("Goose", ["goose"], 165),
        Food("Turkey", ["turkey", "turkey breast", "ground turkey"], 150),
        Food("Veal", ["veal"], 140),
        Food("Duck", ["duck", "duck breast"], 140),
        Food("Chicken breast", ["chicken breast", "chicken breasts", "grilled chicken", "chicken"], 140),
        Food("Lamb", ["lamb", "lamb chop", "lamb chops", "mutton", "gyro"], 130),
        Food("Fried chicken", ["fried chicken", "chicken tenders", "chicken strips"], 130),
        Food("Chicken thigh", ["chicken thigh", "chicken thighs", "chicken leg", "chicken drumstick", "drumstick"], 120),
        Food("Pork", ["pork", "pork chop", "pork chops", "pork loin", "pork tenderloin", "pulled pork", "pork belly"], 120),
        Food("Bacon", ["bacon"], 120),
        Food("Ham", ["ham", "prosciutto"], 120),
        Food("Salami", ["salami", "chorizo"], 120),
        Food("Beef", ["beef", "steak", "ground beef", "roast beef", "brisket", "ribeye", "sirloin", "filet mignon", "corned beef"], 110),
        Food("Chicken wings", ["chicken wings", "chicken wing", "wings"], 110),
        Food("Pepperoni", ["pepperoni"], 110),
        Food("Rabbit", ["rabbit"], 110),
        Food("Venison", ["venison", "deer", "elk", "bison", "game"], 105),
        Food("Sausage", ["sausage", "sausages", "bratwurst", "kielbasa"], 100),
        Food("Meatballs", ["meatball", "meatballs", "meatloaf"], 100),
        Food("Hamburger", ["hamburger", "cheeseburger", "burger", "burgers"], 100),
        Food("Chicken nuggets", ["chicken nuggets", "nuggets"], 100),
        Food("Hot dog", ["hot dog", "hot dogs", "frankfurter", "wiener"], 90),

        // Mixed dishes
        Food("Beef stew", ["beef stew", "stew", "pot roast", "goulash"], 80),
        Food("Curry", ["chicken curry", "beef curry", "lamb curry", "curry"], 80),
        Food("Tacos", ["taco", "tacos", "beef tacos"], 80),
        Food("Chili", ["chili", "chili con carne"], 70),
        Food("Burrito", ["burrito", "burritos"], 60),
        Food("Lasagna", ["lasagna", "lasagne"], 60),
        Food("Bolognese", ["bolognese", "spaghetti bolognese", "spaghetti and meatballs", "meat sauce"], 60),
        Food("Pizza", ["pizza"], 60),
        Food("Ramen", ["ramen", "pho", "tonkotsu"], 60),
        Food("Sandwich", ["sandwich", "sub", "hoagie", "blt", "club sandwich"], 60),
        Food("Fried rice", ["fried rice"], 40),
        Food("Chicken soup", ["chicken soup", "chicken noodle soup"], 40),
        Food("Lentil soup", ["lentil soup"], 40),

        // Legumes and soy
        Food("Soybeans", ["soybean", "soybeans", "natto"], 110),
        Food("Tempeh", ["tempeh"], 110),
        Food("Tofu", ["tofu", "bean curd"], 70),
        Food("Black beans", ["black beans", "black bean"], 60),
        Food("Edamame", ["edamame"], 60),
        Food("Peas", ["peas", "green peas", "split peas", "split pea soup"], 60),
        Food("Lentils", ["lentil", "lentils", "dal", "dahl"], 55),
        Food("Chickpeas", ["chickpea", "chickpeas", "garbanzo", "garbanzo beans", "falafel"], 55),
        Food("Kidney beans", ["kidney beans", "pinto beans", "navy beans", "white beans", "cannellini", "beans"], 55),
        Food("Baked beans", ["baked beans", "refried beans"], 50),
        Food("Hummus", ["hummus", "houmous"], 35),
        Food("Soy milk", ["soy milk", "soymilk"], 20),

        // Vegetables and mushrooms
        Food("Dried shiitake", ["dried shiitake", "shiitake"], 380),
        Food("Broccoli", ["broccoli"], 70),
        Food("Brussels sprouts", ["brussels sprouts", "brussel sprouts"], 70),
        Food("Mushrooms", ["mushroom", "mushrooms", "portobello", "cremini"], 60),
        Food("Spinach", ["spinach"], 55),
        Food("Cauliflower", ["cauliflower"], 50),
        Food("Kale", ["kale"], 50),
        Food("Corn", ["corn", "sweetcorn", "corn on the cob"], 50),
        Food("Green beans", ["green beans", "string beans"], 40),
        Food("Asparagus", ["asparagus"], 25),
        Food("Avocado", ["avocado", "guacamole"], 20),
        Food("Potato", ["potato", "potatoes", "fries", "french fries", "mashed potatoes", "hash browns"], 15),
        Food("Sweet potato", ["sweet potato", "sweet potatoes", "yam", "yams"], 15),
        Food("Carrot", ["carrot", "carrots"], 15),
        Food("Garlic", ["garlic"], 15),
        Food("Zucchini", ["zucchini", "courgette"], 15),
        Food("Tomato", ["tomato", "tomatoes", "tomato sauce", "salsa"], 10),
        Food("Onion", ["onion", "onions"], 10),
        Food("Lettuce", ["lettuce", "salad", "green salad", "garden salad", "caesar salad"], 10),
        Food("Bell pepper", ["bell pepper", "bell peppers", "capsicum"], 10),
        Food("Cucumber", ["cucumber", "cucumbers", "pickle", "pickles"], 5),

        // Grains and baked goods
        Food("Wheat germ", ["wheat germ", "wheat bran"], 190),
        Food("Rolled oats", ["rolled oats", "oats", "dry oats", "oat bran"], 95),
        Food("Granola", ["granola", "muesli"], 50),
        Food("Whole wheat bread", ["whole wheat bread", "wholemeal bread", "whole grain bread", "rye bread"], 40),
        Food("Oatmeal", ["oatmeal", "porridge"], 30),
        Food("Brown rice", ["brown rice"], 30),
        Food("Cereal", ["cereal", "corn flakes", "cornflakes", "bran flakes"], 30),
        Food("Quinoa", ["quinoa"], 25),
        Food("Rice", ["rice", "white rice", "jasmine rice", "basmati rice", "sticky rice", "rice bowl"], 20),
        Food("Pasta", ["pasta", "spaghetti", "penne", "macaroni", "noodles", "linguine", "fettuccine", "ravioli", "gnocchi"], 20),
        Food("Mac and cheese", ["mac and cheese", "macaroni and cheese"], 20),
        Food("Bagel", ["bagel", "bagels"], 20),
        Food("Crackers", ["cracker", "crackers", "pretzel", "pretzels"], 20),
        Food("Tortilla", ["tortilla", "tortillas", "wrap", "naan", "pita"], 20),
        Food("Bread", ["bread", "toast", "white bread", "sourdough", "baguette", "roll", "bun", "croissant"], 15),
        Food("Pancakes", ["pancake", "pancakes", "waffle", "waffles", "french toast", "crepe", "crepes"], 15),

        // Nuts and seeds
        Food("Sunflower seeds", ["sunflower seeds", "sunflower seed"], 140),
        Food("Pumpkin seeds", ["pumpkin seeds", "pepitas"], 120),
        Food("Peanuts", ["peanut", "peanuts"], 80),
        Food("Peanut butter", ["peanut butter"], 65),
        Food("Sesame", ["sesame", "sesame seeds", "tahini"], 60),
        Food("Cashews", ["cashew", "cashews"], 50),
        Food("Chia seeds", ["chia", "chia seeds", "flaxseed", "flax seeds", "flax"], 50),
        Food("Pistachios", ["pistachio", "pistachios"], 40),
        Food("Almonds", ["almond", "almonds", "almond butter"], 35),
        Food("Walnuts", ["walnut", "walnuts", "pecan", "pecans", "hazelnut", "hazelnuts", "macadamia"], 25),

        // Dairy, eggs, protein supplements (low)
        Food("Protein bar", ["protein bar", "protein bars", "granola bar", "energy bar"], 20),
        Food("Whey protein", ["whey protein", "protein shake", "protein powder", "whey"], 10),
        Food("Cheese", ["cheese", "cheddar", "mozzarella", "parmesan", "feta", "brie", "gouda", "swiss cheese", "cottage cheese", "cream cheese", "ricotta"], 5),
        Food("Eggs", ["egg", "eggs", "omelet", "omelette", "scrambled eggs", "fried egg", "boiled egg", "egg whites"], 5),
        Food("Ice cream", ["ice cream", "gelato", "frozen yogurt"], 5),
        Food("Milk", ["milk", "whole milk", "skim milk", "latte", "cappuccino", "oat milk", "almond milk"], 0),
        Food("Yogurt", ["yogurt", "yoghurt", "greek yogurt", "kefir"], 0),
        Food("Butter", ["butter", "cream", "sour cream", "whipped cream", "ghee"], 0),

        // Fruit
        Food("Raisins", ["raisin", "raisins", "dates", "dried fruit", "prunes", "dried apricots"], 30),
        Food("Grapes", ["grape", "grapes"], 20),
        Food("Strawberries", ["strawberry", "strawberries", "raspberry", "raspberries", "blackberries"], 15),
        Food("Pineapple", ["pineapple"], 15),
        Food("Apple", ["apple", "apples", "applesauce"], 10),
        Food("Banana", ["banana", "bananas"], 10),
        Food("Orange", ["orange", "oranges", "mandarin", "clementine", "grapefruit"], 10),
        Food("Blueberries", ["blueberry", "blueberries", "cherries", "cherry"], 10),
        Food("Watermelon", ["watermelon", "melon", "cantaloupe", "honeydew"], 10),
        Food("Mango", ["mango", "peach", "peaches", "pear", "pears", "plum", "plums", "kiwi", "papaya"], 10),

        // Drinks
        Food("Beer", ["beer", "lager", "ale", "ipa", "stout", "pilsner"], 15),
        Food("Non-alcoholic beer", ["non alcoholic beer", "nonalcoholic beer", "alcohol free beer"], 10),
        Food("Orange juice", ["orange juice", "apple juice", "juice", "smoothie"], 10),
        Food("Wine", ["wine", "red wine", "white wine", "rose", "prosecco", "champagne", "sake"], 5),
        Food("Spirits", ["vodka", "whiskey", "whisky", "gin", "rum", "tequila", "bourbon", "brandy", "cocktail", "margarita", "martini", "mojito"], 0),
        Food("Coffee", ["coffee", "espresso", "americano", "cold brew"], 0),
        Food("Tea", ["tea", "green tea", "black tea", "matcha", "chai"], 0),
        Food("Soda", ["soda", "cola", "coke", "pepsi", "sprite", "lemonade", "energy drink", "sports drink", "water", "sparkling water"], 0),

        // Sweets, fats, condiments
        Food("Cocoa", ["cocoa", "cacao", "hot chocolate"], 70),
        Food("Dark chocolate", ["dark chocolate"], 60),
        Food("Chocolate", ["chocolate", "milk chocolate", "brownie", "brownies"], 40),
        Food("Cookies", ["cookie", "cookies", "biscuit", "biscuits", "cake", "muffin", "muffins", "donut", "doughnut", "pastry", "pie"], 15),
        Food("Jam", ["jam", "jelly", "marmalade", "mayonnaise", "mayo", "ketchup", "mustard"], 5),
        Food("Sugar", ["sugar", "honey", "syrup", "maple syrup", "candy", "gummies", "marshmallow"], 0),
        Food("Oil", ["olive oil", "oil", "vegetable oil", "coconut oil", "margarine", "vinaigrette", "dressing"], 0),
    ]

    /// The reference food whose longest keyword appears as whole words in `text`, or nil.
    nonisolated static func match(_ text: String, in foods: [Food] = foods) -> Food? {
        let haystack = " " + normalized(text) + " "
        guard haystack.count > 2 else { return nil }
        var best: (food: Food, length: Int)?
        for food in foods {
            for keyword in food.keywords {
                let key = normalized(keyword)
                guard !key.isEmpty, containsWord(key, in: haystack) else { continue }
                if best == nil || key.count > best!.length {
                    best = (food, key.count)
                }
            }
        }
        return best?.food
    }

    /// Estimated purines (mg) for the analyzed amount, or nil when nothing in the entry is recognized.
    ///
    /// Ingredient breakdowns are preferred (each ingredient by its own grams); otherwise the
    /// entry name is matched and scaled by its serving size (100 g when the weight is unknown).
    nonisolated static func estimateMilligrams(for entry: FoodEntry) -> Double? {
        estimateMilligrams(name: entry.name, grams: entry.servingSizeGrams, ingredients: entry.ingredients)
    }

    nonisolated static func estimateMilligrams(name: String, grams: Double?, ingredients: [MealIngredient], in foods: [Food] = foods) -> Double? {
        if !ingredients.isEmpty {
            var total = 0.0
            var matchedAny = false
            for ingredient in ingredients {
                guard let food = match(ingredient.name, in: foods) else { continue }
                matchedAny = true
                total += food.milligramsPer100g * max(ingredient.grams, 0) / 100
            }
            if matchedAny { return rounded(total) }
        }
        guard let food = match(name, in: foods) else { return nil }
        let weight = (grams ?? 0) > 0 ? grams! : assumedGrams
        return rounded(food.milligramsPer100g * weight / 100)
    }

    /// Adds a purine estimate to `supplementalNutrients` when the entry has none and a reference
    /// food matches. Entries that already carry a value (from the AI, a label or the user) are untouched.
    nonisolated static func applyFallbackIfNeeded(_ entry: inout FoodEntry) {
        guard entry.supplementalNutrients[storageKey] == nil,
              let estimate = estimateMilligrams(for: entry)
        else { return }
        entry.supplementalNutrients[storageKey] = estimate
    }

    // MARK: - Helpers

    nonisolated private static func normalized(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
        var out = ""
        var lastWasSpace = true
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                out.unicodeScalars.append(scalar)
                lastWasSpace = false
            } else if !lastWasSpace {
                out.append(" ")
                lastWasSpace = true
            }
        }
        return out.trimmingCharacters(in: .whitespaces)
    }

    nonisolated private static func containsWord(_ key: String, in haystack: String) -> Bool {
        for form in [key, key + "s", key + "es"] where haystack.contains(" " + form + " ") {
            return true
        }
        if key.hasSuffix("y"), haystack.contains(" " + String(key.dropLast()) + "ies ") {
            return true
        }
        return false
    }

    nonisolated private static func rounded(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }
}
