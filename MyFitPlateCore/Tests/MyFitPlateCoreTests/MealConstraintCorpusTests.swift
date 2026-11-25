import XCTest
@testable import MyFitPlateCore

/// Deterministic validation corpus, not a model-quality, label-safety or clinical benchmark.
/// Each row is a distinct meal/ingredient description. Opaque branded/sauced foods remain
/// unverified; personal review never overrides a detected contradiction.
final class MealConstraintCorpusTests: XCTestCase {
    func testTwoHundredDistinctMealDescriptions() throws {
        let rows = Self.corpus.split(separator: "\n").map { $0.split(separator: "|", omittingEmptySubsequences: false).map(String.init) }
        XCTAssertEqual(rows.count, 200)
        XCTAssertEqual(Set(rows.map { $0[0] }).count, 200)
        for (index, row) in rows.enumerated() {
            XCTAssertEqual(row.count, 6)
            let diet = try XCTUnwrap(PlanningDiet(rawValue: row[2]))
            let profile = MealConstraintProfile(revisionID: "corpus-\(index)", diet: diet,
                hardExclusions: row[1].isEmpty ? [] : [row[1]])
            let ingredients = row[5].split(separator: ";").map(String.init)
            let candidate = MealConstraintCandidate(name: row[0], ingredients: ingredients, instructions: "Prepare the listed ingredients.",
                food: FoodItem(id: "food-\(index)", name: row[0], calories: 500, protein: 25, carbs: 60, fats: 18))
            let suggestion = MealSuggestion(title: row[0], calories: 500, mealName: row[0], protein: 25, carbs: 60, fats: 18,
                ingredients: ingredients, instructions: "Prepare the listed ingredients.").withGeneratedEvidence()
            XCTAssertTrue(MealSuggestionFeasibilityRules.fitsGeneration(suggestion, remaining: .init(calories: 500, protein: 25, carbs: 60, fats: 18)))
            XCTAssertFalse(MealSuggestionFeasibilityRules.fitsGeneration(suggestion, remaining: .init(calories: 0, protein: 25, carbs: 60, fats: 18)))
            XCTAssertFalse(MealSuggestionFeasibilityRules.fitsGeneration(suggestion, remaining: .init(calories: 499, protein: 25, carbs: 60, fats: 18)))
            XCTAssertEqual(suggestion.feasibility?.unresolvedCount, ingredients.count, "Corpus quantities are proposed text, never verified nutrients")
            let review = row[4] == "current" ? MealIngredientReview(candidate: candidate, profile: profile) : nil
            let report = MealConstraintRules.report(candidate: candidate, profile: profile, personalReview: review)
            let status = report.isBlocked ? "blocked" : report.needsPersonalReview ? "review" : "allowed"
            XCTAssertEqual(status, row[3], "Corpus \(index + 1): \(row[0]); \(report.issues.map(\.message))")
        }
    }

    private static let corpus = """
    Satay chicken bowl|peanut|unrestricted|blocked|none|150 g chicken;30 g peanut butter;100 g cooked rice
    Groundnut greens stew|peanut|unrestricted|blocked|none|200 g greens;20 ml groundnut oil;100 g sweet potato
    Crunchy apple snack|peanut|unrestricted|blocked|none|1 apple;25 g chopped peanuts
    Peanut noodle salad|peanut|unrestricted|blocked|none|120 g noodles;15 g peanut paste;50 g cucumber
    Roasted nut trail mix|peanut|unrestricted|blocked|none|20 g raisins;30 g roasted peanut;10 g sunflower seeds
    Chocolate spread toast|peanut|unrestricted|blocked|none|1 slice toast;20 g chocolate peanut spread
    West African squash soup|peanut|unrestricted|blocked|none|250 g squash;30 g groundnut paste
    Peanut flour pancakes|peanut|unrestricted|blocked|none|40 g peanut flour;100 ml water;1 egg
    Crunch topping yogurt|peanut|unrestricted|blocked|none|150 g yogurt;15 g crushed peanuts
    Chili nut tofu stir fry|peanut|unrestricted|blocked|none|150 g tofu;20 g peanut oil;100 g peppers
    Peanut date energy bites|peanut|unrestricted|blocked|none|60 g dates;25 g peanut meal;10 g oats
    Spicy peanut-free claim bowl|peanut|unrestricted|blocked|none|100 g rice;15 g peanut butter;50 g carrots
    Creamy tomato pasta|dairy|unrestricted|blocked|none|150 g pasta;40 ml cream;100 g tomato
    Cheddar potato bake|dairy|unrestricted|blocked|none|200 g potato;40 g cheddar cheese
    Whey banana shake|dairy|unrestricted|blocked|none|1 banana;30 g whey powder;200 ml water
    Butter mushroom toast|dairy|unrestricted|blocked|none|1 slice bread;15 g butter;80 g mushrooms
    Ghee lentil dal|dairy|unrestricted|blocked|none|150 g lentils;10 g ghee;50 g tomatoes
    Greek yogurt fruit bowl|dairy|unrestricted|blocked|none|170 g yogurt;80 g blueberries
    Milk porridge|dairy|unrestricted|blocked|none|50 g oats;200 ml milk;1 tsp cinnamon
    Cottage cheese peach plate|dairy|unrestricted|blocked|none|150 g cottage cheese;1 peach
    Casein cocoa pudding|dairy|unrestricted|blocked|none|30 g casein powder;200 ml water;10 g cocoa
    Ricotta-style cream ravioli|dairy|unrestricted|blocked|none|150 g ravioli;60 ml dairy cream
    Parmesan broccoli rice|dairy|unrestricted|blocked|none|100 g rice;20 g parmesan cheese;100 g broccoli
    Yoghurt mint dip|dairy|unrestricted|blocked|none|120 g yoghurt;10 g mint;1 cucumber
    Tofu rice bowl|soy|unrestricted|blocked|none|150 g tofu;100 g rice;100 g broccoli
    Miso mushroom soup|soy|unrestricted|blocked|none|10 g miso;150 g mushrooms;200 ml broth
    Edamame avocado salad|soy|unrestricted|blocked|none|100 g edamame;50 g avocado;100 g lettuce
    Tamari ginger salmon|soy|unrestricted|blocked|none|150 g salmon;10 ml tamari;5 g ginger
    Tempeh roasted vegetable plate|soy|unrestricted|blocked|none|120 g tempeh;100 g courgette;80 g peppers
    Soy milk overnight oats|soy|unrestricted|blocked|none|50 g oats;180 ml soy milk;50 g berries
    Soya mince chili|soy|unrestricted|blocked|none|100 g soya mince;100 g kidney beans;100 g tomato
    Soy flour flatbread|soy|unrestricted|blocked|none|40 g soy flour;50 ml water;5 ml oil
    Crispy tofu noodle soup|soy|unrestricted|blocked|none|100 g tofu;120 g noodles;200 ml broth
    Soy sauce fried rice|soy|unrestricted|blocked|none|150 g rice;15 ml soy sauce;50 g peas
    Miso glazed aubergine|soy|unrestricted|blocked|none|200 g aubergine;15 g miso;5 g sugar
    Soy protein breakfast shake|soy|unrestricted|blocked|none|30 g soy protein;1 banana;200 ml water
    Spinach breakfast omelet|egg|unrestricted|blocked|none|2 eggs;50 g spinach;5 ml oil
    Mayonnaise tuna wrap|egg|unrestricted|blocked|none|1 wrap;100 g tuna;20 g mayonnaise
    Albumen protein pancakes|egg|unrestricted|blocked|none|30 g albumen;40 g oats;100 ml water
    Egg noodle vegetable soup|egg|unrestricted|blocked|none|100 g egg noodles;150 g vegetables;200 ml broth
    Poached egg avocado toast|egg|unrestricted|blocked|none|1 egg;1 slice bread;50 g avocado
    Egg wash pastry|egg|unrestricted|blocked|none|100 g pastry;15 g egg wash;50 g apple
    Scrambled egg rice|egg|unrestricted|blocked|none|150 g rice;2 eggs;50 g peas
    Potato mayonnaise salad|egg|unrestricted|blocked|none|180 g potato;25 g mayonnaise;20 g celery
    Egg white oat muffins|egg|unrestricted|blocked|none|60 g egg white;40 g oats;1 banana
    Deviled egg plate|egg|unrestricted|blocked|none|2 eggs;15 g mayonnaise;5 g mustard
    Carbonara breakfast bowl|egg|unrestricted|blocked|none|100 g pasta;1 egg;20 g cheese
    Egg custard fruit cup|egg|unrestricted|blocked|none|1 egg;150 ml milk;50 g berries
    Bulgur parsley salad|wheat|unrestricted|blocked|none|150 g bulgur;30 g parsley;50 g tomato
    Couscous chickpea bowl|wheat|unrestricted|blocked|none|130 g couscous;100 g chickpeas;50 g cucumber
    Semolina lemon porridge|wheat|unrestricted|blocked|none|45 g semolina;180 ml milk;5 g lemon zest
    Farro roasted carrot bowl|wheat|unrestricted|blocked|none|120 g farro;150 g carrots;20 g feta cheese
    Spelt breakfast toast|wheat|unrestricted|blocked|none|2 slices spelt bread;20 g jam
    Wheat tortilla bean wrap|wheat|unrestricted|blocked|none|1 wheat tortilla;100 g beans;40 g salsa
    Whole wheat pasta primavera|wheat|unrestricted|blocked|none|140 g whole wheat pasta;150 g vegetables
    Wheat flour berry pancakes|wheat|unrestricted|blocked|none|50 g wheat flour;80 ml milk;60 g berries
    Cracked wheat vegetable pilaf|wheat|unrestricted|blocked|none|100 g cracked wheat;80 g carrots;50 g peas
    Bulgur lentil patties|wheat|unrestricted|blocked|none|80 g bulgur;80 g lentils;20 g onion
    Semolina gnocchi bake|wheat|unrestricted|blocked|none|100 g semolina;100 ml milk;20 g cheese
    Farro mushroom risotto|wheat|unrestricted|blocked|none|130 g farro;100 g mushrooms;150 ml broth
    Tahini lemon chickpeas|sesame|unrestricted|blocked|none|100 g chickpeas;20 g tahini;10 ml lemon juice
    Sesame crusted salmon|sesame|unrestricted|blocked|none|150 g salmon;15 g sesame seeds
    Sesame oil vegetable noodles|sesame|unrestricted|blocked|none|130 g noodles;10 ml sesame oil;80 g vegetables
    Tahini yogurt cucumber dip|sesame|unrestricted|blocked|none|100 g yogurt;15 g tahini;60 g cucumber
    Sesame bagel breakfast|sesame|unrestricted|blocked|none|1 sesame bagel;40 g cream cheese
    Sesame spinach side|sesame|unrestricted|blocked|none|100 g spinach;10 g sesame seeds;5 ml tamari
    Tahini cocoa oats|sesame|unrestricted|blocked|none|50 g oats;15 g tahini;5 g cocoa
    Roasted sesame tofu|sesame|unrestricted|blocked|none|150 g tofu;10 g roasted sesame;80 g cabbage
    Sesame seed crackers|sesame|unrestricted|blocked|none|40 g sesame seed crackers;50 g hummus
    Black sesame rice pudding|sesame|unrestricted|blocked|none|100 g rice;10 g black sesame;100 ml milk
    Tahini apple toast|sesame|unrestricted|blocked|none|1 slice bread;15 g tahini;1 sliced apple
    Sesame ginger dressing salad|sesame|unrestricted|blocked|none|150 g lettuce;15 ml sesame dressing;20 g carrot
    Salmon potato tray bake|fish|unrestricted|blocked|none|150 g salmon;180 g potatoes;80 g asparagus
    Tuna white bean salad|fish|unrestricted|blocked|none|100 g tuna;100 g white beans;50 g celery
    Cod tomato stew|fish|unrestricted|blocked|none|150 g cod;150 g tomato;80 g potato
    Anchovy garlic spaghetti|fish|unrestricted|blocked|none|120 g spaghetti;10 g anchovies;5 g garlic
    Sardine toast lunch|fish|unrestricted|blocked|none|90 g sardines;2 slices bread;50 g tomato
    Trout rice dinner|fish|unrestricted|blocked|none|160 g trout;120 g rice;100 g greens
    Mackerel lentil salad|fish|unrestricted|blocked|none|100 g mackerel;120 g lentils;50 g cucumber
    Bonito rice ball|fish|unrestricted|blocked|none|100 g rice;10 g bonito flakes;1 sheet seaweed
    Fish sauce vegetable curry|fish|unrestricted|blocked|none|150 g vegetables;10 ml fish sauce;100 ml coconut milk
    Tuna sushi roll|fish|unrestricted|blocked|none|100 g sushi rice;50 g tuna;20 g cucumber
    Salmon breakfast omelet|fish|unrestricted|blocked|none|2 eggs;60 g smoked salmon;20 g onion
    Anchovy olive tapenade|fish|unrestricted|blocked|none|10 g anchovy;40 g olives;1 slice toast
    Shrimp garlic rice|shellfish|unrestricted|blocked|none|130 g shrimp;120 g rice;5 g garlic
    Prawn avocado salad|shellfish|unrestricted|blocked|none|100 g prawns;60 g avocado;100 g lettuce
    Crab cucumber sushi|shellfish|unrestricted|blocked|none|60 g crab;100 g rice;30 g cucumber
    Lobster pasta dinner|shellfish|unrestricted|blocked|none|100 g lobster;130 g pasta;50 g tomato
    Clam tomato broth|shellfish|unrestricted|blocked|none|120 g clams;200 ml broth;100 g tomato
    Mussel garlic pot|shellfish|unrestricted|blocked|none|160 g mussels;10 g garlic;100 ml broth
    Oyster mushroom starter|shellfish|unrestricted|blocked|none|60 g oysters;80 g mushrooms;5 ml oil
    Scallop pea risotto|shellfish|unrestricted|blocked|none|120 g scallops;100 g rice;50 g peas
    Crayfish corn bowl|shellfish|unrestricted|blocked|none|100 g crayfish;80 g corn;100 g rice
    Shrimp paste vegetable curry|shellfish|unrestricted|blocked|none|10 g shrimp paste;150 g vegetables;100 ml coconut milk
    Crab cake lunch|shellfish|unrestricted|blocked|none|100 g crab meat;20 g breadcrumbs;1 egg
    Prawn chili noodles|shellfish|unrestricted|blocked|none|120 g prawn;130 g noodles;5 g chili
    Almond apple snack|tree nuts|unrestricted|blocked|none|1 apple;20 g almonds
    Cashew cream pasta|tree nuts|unrestricted|blocked|none|130 g pasta;30 g cashew cream;100 g spinach
    Walnut beetroot salad|tree nuts|unrestricted|blocked|none|150 g beetroot;20 g walnut;50 g leaves
    Pecan oat crumble|tree nuts|unrestricted|blocked|none|40 g oats;20 g pecans;100 g apple
    Pistachio yogurt bowl|tree nuts|unrestricted|blocked|none|150 g yogurt;20 g pistachios;50 g berries
    Hazelnut chocolate toast|tree nuts|unrestricted|blocked|none|1 slice bread;20 g hazelnut spread
    Macadamia coconut bites|tree nuts|unrestricted|blocked|none|20 g macadamia;20 g coconut;40 g dates
    Brazil nut raisin mix|tree nuts|unrestricted|blocked|none|20 g brazil nuts;20 g raisins;10 g seeds
    Almond flour waffles|tree nuts|unrestricted|blocked|none|50 g almond flour;1 egg;100 ml milk
    Cashew vegetable stir fry|tree nuts|unrestricted|blocked|none|30 g cashews;150 g vegetables;100 g rice
    Walnut pesto pasta|tree nuts|unrestricted|blocked|none|20 g walnuts;10 g basil;130 g pasta
    Pecan maple granola|tree nuts|unrestricted|blocked|none|50 g oats;20 g pecan;10 g maple syrup
    Honey lemon oats||vegan|blocked|none|50 g oats;10 g honey;150 ml oat milk
    Butter sauteed carrots||vegan|blocked|none|150 g carrots;10 g butter;5 g parsley
    Egg breakfast potato||vegan|blocked|none|1 egg;180 g potato;50 g spinach
    Salmon grain salad||vegan|blocked|none|100 g salmon;120 g rice;50 g greens
    Whey recovery smoothie||vegan|blocked|none|30 g whey;1 banana;200 ml water
    Yogurt cucumber bowl||vegan|blocked|none|150 g yogurt;100 g cucumber;10 g dill
    Cheese tomato sandwich||vegan|blocked|none|2 slices bread;40 g cheese;80 g tomato
    Chicken soup supper||vegan|blocked|none|100 g chicken;200 ml broth;100 g vegetables
    Turkey cranberry wrap||vegetarian|blocked|none|1 wrap;120 g turkey;20 g cranberry sauce
    Beef broccoli noodles||vegetarian|blocked|none|120 g beef;100 g broccoli;130 g noodles
    Chicken noodle lunch||vegetarian|blocked|none|120 g chicken;100 g noodles;80 g carrots
    Tuna pepper pita||vegetarian|blocked|none|1 pita;90 g tuna;60 g pepper
    Fish sauce cabbage||vegetarian|blocked|none|150 g cabbage;10 ml fish sauce;5 ml oil
    Shrimp coconut curry||vegetarian|blocked|none|100 g shrimp;100 ml coconut milk;100 g rice
    Pork vegetable dumplings||vegetarian|blocked|none|100 g pork;80 g cabbage;100 g wrappers
    Gelatin raspberry dessert||vegetarian|blocked|none|5 g gelatin;100 g raspberries;150 ml juice
    Bacon mushroom omelet||pescatarian|blocked|none|2 eggs;30 g bacon;80 g mushrooms
    Ham pea pasta||pescatarian|blocked|none|120 g pasta;50 g ham;60 g peas
    Lamb lentil stew||pescatarian|blocked|none|100 g lamb;100 g lentils;150 ml broth
    Duck roast potatoes||pescatarian|blocked|none|120 g duck;180 g potato;100 g greens
    Venison bean chili||pescatarian|blocked|none|120 g venison;100 g beans;100 g tomato
    Veal tomato meatballs||pescatarian|blocked|none|120 g veal;100 g tomato;100 g rice
    Lard fried beans||pescatarian|blocked|none|150 g beans;10 g lard;30 g onion
    Chicken stock risotto||pescatarian|blocked|none|120 g rice;150 ml chicken stock;80 g mushrooms
    Bol de mani y arroz|peanut|unrestricted|blocked|none|100 g arroz;20 g maní tostado
    Tostada de cacahuete|peanut|unrestricted|blocked|none|1 tostada;20 g crema de cacahuete
    Salade aux arachides|peanut|unrestricted|blocked|none|100 g salade;20 g arachides
    Erdnuss Reis Schale|peanut|unrestricted|blocked|none|120 g reis;20 g erdnuss
    Avena con leche|milk|unrestricted|blocked|none|50 g avena;200 ml leche
    Riz au lait|milk|unrestricted|blocked|none|100 g riz;150 ml lait
    Milch Hafer Brei|milk|unrestricted|blocked|none|50 g hafer;200 ml milch
    Arroz con huevo|egg|unrestricted|blocked|none|100 g arroz;1 huevo
    Salade avec oeuf|egg|unrestricted|blocked|none|100 g salade;1 oeuf
    Riz et œuf|egg|unrestricted|blocked|none|100 g riz;1 œuf
    Arroz con sesamo|sesame|unrestricted|blocked|none|100 g arroz;10 g sésamo
    Salade au sesame|sesame|unrestricted|blocked|none|100 g salade;10 g sésame
    Pan de trigo|wheat|unrestricted|blocked|none|100 g pan de trigo
    Salade de ble|wheat|unrestricted|blocked|none|120 g blé;50 g tomate
    Sopa de soja|soy|unrestricted|blocked|none|100 g soja;200 ml caldo
    Arroz con pescado|fish|unrestricted|blocked|none|100 g arroz;120 g pescado
    House curry takeaway|peanut|unrestricted|review|none|1 tray house curry;1 portion rice
    Street noodle lunch|peanut|unrestricted|review|none|1 bowl vendor noodles;1 ladle mystery sauce
    Deli grain salad|peanut|unrestricted|review|none|1 tub deli grain salad;1 packet house dressing
    Stir fry kit dinner|peanut|unrestricted|review|none|1 ready stir-fry kit;1 sauce sachet
    Bakery breakfast muffin|dairy|unrestricted|review|none|1 bakery muffin;1 cup coffee
    Silky vegetable soup|dairy|unrestricted|review|none|1 bowl restaurant soup;1 bread roll
    Ready lasagne dinner|dairy|unrestricted|review|none|1 chilled lasagne;1 side salad
    Protein bar desk snack|dairy|unrestricted|review|none|1 packaged protein bar;1 apple
    Takeaway rice with house sauce|sesame|unrestricted|review|none|150 g rice;30 g house sauce
    Falafel shop plate|sesame|unrestricted|review|none|4 falafel;1 serving white sauce
    Restaurant roasted vegetables|sesame|unrestricted|review|none|200 g roasted vegetables;1 garnish packet
    Catered sandwich platter|sesame|unrestricted|review|none|1 catered sandwich;1 condiment sachet
    Family recipe pancake|egg|unrestricted|review|none|2 family recipe pancakes;1 spoon syrup
    Store-bought potato salad|egg|unrestricted|review|none|150 g prepared potato salad;50 g lettuce
    Cafe wrap special|egg|unrestricted|review|none|1 cafe special wrap;1 portion fries
    Bakery savory tart|egg|unrestricted|review|none|1 savory tart;100 g greens
    Gym protein drink|soy|unrestricted|review|none|1 premixed protein drink;1 banana
    Brand ready dinner|soy|unrestricted|review|none|1 ready dinner tray;1 side cucumber
    Marinated vegetable skewers|soy|unrestricted|review|none|2 prepared skewers;1 portion rice
    Deli veggie burger|soy|unrestricted|review|none|1 prepared vegetable patty;1 bun
    Eggplant tomato rice|egg|unrestricted|allowed|current|150 g eggplant;100 g tomato;120 g rice
    Aubergine garlic tray|egg|unrestricted|allowed|current|180 g aubergine;5 g garlic;5 ml oil
    Coconut milk rice soup|dairy|unrestricted|allowed|current|150 ml coconut milk;100 g rice;5 g ginger
    Almond butter banana oats|dairy|unrestricted|allowed|current|20 g almond butter;50 g oats;1 banana
    Oat milk blueberry bowl|dairy|unrestricted|allowed|current|150 ml oat milk;50 g oats;80 g blueberries
    Cashew cream spinach pasta|dairy|unrestricted|allowed|current|30 g cashew cream;100 g spinach;130 g pasta
    Plant cheese potato toast|dairy|unrestricted|allowed|current|20 g plant cheese;100 g potato;1 slice bread
    Vegan yogurt pear snack|dairy|unrestricted|allowed|current|150 g vegan yogurt;1 pear
    Sunflower butter pear toast|peanut|unrestricted|allowed|current|20 g sunflower seed butter;1 pear;1 slice bread
    Chickpea cucumber lemon bowl|peanut|unrestricted|allowed|current|150 g chickpeas;100 g cucumber;10 ml lemon juice
    Black bean corn salad|peanut|unrestricted|allowed|current|100 g black beans;80 g corn;50 g tomato
    Lentil carrot soup|peanut|unrestricted|allowed|current|150 g lentils;100 g carrots;200 ml water
    Olive oil zucchini pasta|sesame|unrestricted|allowed|current|10 ml olive oil;150 g zucchini;120 g pasta
    Lemon herb rice salad|sesame|unrestricted|allowed|current|120 g rice;10 ml lemon;10 g parsley
    Pumpkin seed oat bowl|sesame|unrestricted|allowed|current|20 g pumpkin seeds;50 g oats;100 ml water
    Roasted pepper potato plate|sesame|unrestricted|allowed|current|150 g peppers;180 g potatoes;5 ml oil
    Berry cinnamon oatmeal|peanut|unrestricted|review|none|50 g oats;100 g mixed berries;1 tsp cinnamon
    Brown rice kidney bean bowl|peanut|unrestricted|review|none|120 g brown rice;100 g kidney beans;80 g cucumber
    Baked sweet potato hummus|peanut|unrestricted|review|none|200 g sweet potato;50 g hummus
    Quinoa roasted cauliflower|peanut|unrestricted|review|none|120 g quinoa;180 g cauliflower;5 ml oil
    Apple walnut porridge|dairy|unrestricted|review|none|50 g oats;1 apple;20 g walnuts;150 ml water
    Bean tomato chili|dairy|unrestricted|review|none|150 g beans;150 g tomato;50 g pepper
    Tofu cucumber rice|dairy|unrestricted|review|none|150 g tofu;100 g cucumber;120 g rice
    Sardine tomato crackers|dairy|unrestricted|review|none|90 g sardines;60 g tomatoes;4 crackers
    Avocado black bean toast|soy|unrestricted|review|none|50 g avocado;80 g black beans;1 slice bread
    Salmon lemon potatoes|soy|unrestricted|review|none|150 g salmon;180 g potato;10 ml lemon
    Chicken carrot rice|soy|unrestricted|review|none|150 g chicken;100 g carrots;120 g rice
    Banana chia pudding|soy|unrestricted|review|none|1 banana;20 g chia;150 ml oat milk
    Roasted chickpea beet salad|sesame|unrestricted|review|none|100 g chickpeas;150 g beetroot;50 g lettuce
    Cocoa peanut breakfast oats|sesame|unrestricted|review|none|50 g oats;15 g peanut butter;5 g cocoa
    Turkey rice lettuce cups|sesame|unrestricted|review|none|120 g turkey;100 g rice;4 lettuce leaves
    Lemon shrimp quinoa bowl|sesame|unrestricted|review|none|120 g shrimp;100 g quinoa;10 ml lemon
    """
}
