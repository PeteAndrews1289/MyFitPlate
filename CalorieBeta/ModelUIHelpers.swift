import SwiftUI

struct CustomCorners: Shape { var corners: UIRectCorner; var radius: CGFloat; func path(in rect: CGRect) -> Path { let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius)); return Path(path.cgPath) } }

struct FoodEmojiMapper {
    static let foodEmojiMap: [String: String] = [
        "hotdog":"🌭","hot dog":"🌭","burger":"🍔","hamburger":"🍔","cheeseburger":"🍔","pizza":"🍕","taco":"🌮","burrito":"🌯","fries":"🍟","sandwich":"🥪","wrap":"🌯","nachos":"🌮",
        "steak":"🥩","chicken":"🍗","fish":"🐟","shrimp":"🍤","prawn":"🍤","egg":"🥚","eggs":"🥚","bacon":"🥓","sausage":"🌭","ham":"🥓","pork":"🥓","beef":"🥩","lamb":"🍖","turkey":"🍗","oyster":"🐚","caviar":"🐟",
        "rice":"🍚","pasta":"🍝","spaghetti":"🍝","ravioli":"🍝","bread":"🍞","toast":"🍞","noodles":"🍜","ramen":"🍜","pho":"🍜","pad thai":"🍜","bagel":"🥯","croissant":"🥐","pretzel":"🥨","bun":"🥐","roll":"🥐",
        "apple":"🍎","banana":"🍌","orange":"🍊","grape":"🍇","strawberry":"🍓","watermelon":"🍉","pear":"🍐","cherry":"🍒","mango":"🥭","pineapple":"🍍","peach":"🍑","kiwi":"🥝","lemon":"🍋","lime":"🍋","blueberry":"🫐","raspberry":"🫐",
        "carrot":"🥕","broccoli":"🥦","tomato":"🍅","potato":"🥔","corn":"🌽","lettuce":"🥬","cucumber":"🥒","onion":"🧅","garlic":"🧄","pepper":"🌶️","mushroom":"🍄","spinach":"🥬","cabbage":"🥬","zucchini":"🥒","eggplant":"🍆",
        "cake":"🍰","carrot cake":"🍰","chocolate cake":"🍰","red velvet cake":"🍰","cheesecake":"🍰","cookie":"🍪","ice cream":"🍦","donut":"🍩","chocolate":"🍫","candy":"🍬","cupcake":"🧁","pie":"🥧","apple pie":"🥧","pudding":"🍮","bread pudding":"🍮","panna cotta":"🍮","waffle":"🧇","pancake":"🥞",
        "coffee":"☕","tea":"🍵","juice":"🍹","beer":"🍺","wine":"🍷","milk":"🥛","cocktail":"🍸","soda":"🥤","water":"💧",
        "sushi":"🍣","sashimi":"🍣","sushi roll":"🍣","curry":"🍛","chicken curry":"🍛","dumpling":"🥟","gyoza":"🥟","samosa":"🥟","egg roll":"🥟","falafel":"🧆","paella":"🍲","tempura":"🍤","cheese":"🧀","grilled cheese":"🧀",
        "peanut":"🥜","popcorn":"🍿","lollipop":"🍭","honey":"🍯","butter":"🧈","oil":"🫒","olive oil":"🫒","soup":"🥣","miso soup":"🥣","french onion soup":"🥣","hot and sour soup":"🥣","clam chowder":"🥣","lobster bisque":"🥣","salad":"🥗","greek salad":"🥗","caesar salad":"🥗","caprese salad":"🥗","beet salad":"🥗","fruit salad":"🥗","stew":"🍲","casserole":"🍲","quesadilla":"🌮",
        "cumin":"🌿", "paprika":"🌶️", "salt":"🧂", "black pepper":"🧂", "cinnamon":"🍂", "nutmeg":"🌰", "oregano":"🌿", "basil":"🌿", "thyme":"🌿", "rosemary":"🌿", "parsley":"🌿", "cilantro":"🌿", "ginger":"🫚", "turmeric":"🫚", "chili powder":"🌶️", "cayenne":"🌶️", "soy sauce":"🥢", "vinegar":"🍾", "mustard":"🌭", "ketchup":"🍅", "mayo":"🥚", "mayonnaise":"🥚", "sugar":"🧂", "flour":"🌾", "oats":"🌾", "quinoa":"🌾", "beans":"🫘", "lentils":"🫘", "chickpeas":"🫘", "almonds":"🥜", "walnuts":"🥜", "cashews":"🥜", "chia":"🌱", "flax":"🌱", "hemp":"🌱", "sunflower seeds":"🌻", "pumpkin seeds":"🎃", "sesame seeds":"🌱", "coconut":"🥥", "avocado":"🥑", "sweet potato":"🍠", "squash":"🎃", "pumpkin":"🎃", "celery":"🥬", "asparagus":"🥬", "green beans":"🫘", "peas":"🫛", "olives":"🫒", "pickles":"🥒", "jalapeno":"🌶️", "habanero":"🌶️", "lime juice":"🍋", "lemon juice":"🍋", "vanilla":"🍦", "cocoa":"🍫", "baking powder":"🧂", "baking soda":"🧂", "yeast":"🍞", "broth":"🥣", "stock":"🥣", "bouillon":"🥣", "wine vinegar":"🍾", "apple cider vinegar":"🍎", "balsamic":"🍾", "maple syrup":"🍁", "agave":"🌵", "peanut butter":"🥜", "almond butter":"🥜", "jam":"🍓", "jelly":"🍇", "marmalade":"🍊", "nutella":"🍫"
    ]

    static func getEmoji(for foodName: String) -> String {
        let l = foodName.lowercased()
        if let e = foodEmojiMap[l] { return e }
        if let c = foodEmojiMap.first(where: { l.contains($0.key) }) { return c.value }
        let w = l.split(separator: " ").map { String($0) }
        if let f = w.first, let m = foodEmojiMap[f] { return m }
        return "🍽️"
    }
}

struct ExerciseEmojiMapper {
    static let exerciseEmojiMap: [String: String] = [
        "running": "🏃", "run": "🏃",
        "walking": "🚶", "walk": "🚶", "power walk": "🚶‍♀️",
        "jogging": "🏃‍♂️",
        "cycling": "🚴", "bike": "🚴", "stationary bike": "🚴‍♀️",
        "swimming": "🏊", "swim": "🏊‍♀️",
        "hiking": "🥾",
        "jumping jacks": "🤸",
        "jump rope": "🤸‍♀️",
        "stair climbing": "🧗", "stairs": "🧗‍♀️",
        "elliptical": "🚲",
        "rowing": "🚣",
        "hiit": "⏱️", "high intensity interval training": "⏱️",
        "strength training": "🏋️", "weights": "🏋️‍♀️", "weight lifting": "🏋️",
        "bodyweight exercises": "🤸‍♂️",
        "push-ups": "💪",
        "pull-ups": "💪",
        "squats": "🦵",
        "lunges": "🦵",
        "deadlifts": "🏋️",
        "bench press": "🏋️",
        "kettlebell": "💣",
        "crossfit": "🏋️‍♂️",
        "calisthenics": "🤸",
        "basketball": "🏀",
        "soccer": "⚽", "football": "⚽",
        "american football": "🏈",
        "tennis": "🎾",
        "volleyball": "🏐",
        "baseball": "⚾",
        "golf": "⛳",
        "skiing": "⛷️",
        "snowboarding": "🏂",
        "boxing": "🥊",
        "martial arts": "🥋",
        "yoga": "🧘", "yoga flow": "🧘‍♀️",
        "pilates": "🧘‍♂️",
        "dancing": "💃", "dance": "🕺",
        "stretching": "🙆",
        "meditation": "🧘",
        "gardening": "🧑‍🌾",
        "cleaning": "🧹"
    ]

    static func getEmoji(for exerciseName: String) -> String {
        let lowercasedName = exerciseName.lowercased()
        if let emoji = exerciseEmojiMap[lowercasedName] {
            return emoji
        }
        for (key, emoji) in exerciseEmojiMap {
            if lowercasedName.contains(key) {
                return emoji
            }
        }
        return "🤸"
    }
}

struct ActionButtonLabel: View { let title: String; let icon: String; @Environment(\.colorScheme) var colorScheme; var body: some View { HStack { Image(systemName: icon).foregroundColor(Color.accentColor).frame(width: 24, height: 24); Text(title).foregroundColor(colorScheme == .dark ? .white : .black).font(.headline); Spacer() }.padding().background(colorScheme == .dark ? Color(.tertiarySystemBackground) : Color(red: 245/255, green: 245/255, blue: 245/255).opacity(0.5)).cornerRadius(12) } }
