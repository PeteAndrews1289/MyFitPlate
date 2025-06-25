
import FirebaseFirestore
import FirebaseAuth


func addSampleLog() {
    let db = Firestore.firestore()

    
    let dailyLog: [String: Any] = [
        "date": Timestamp(date: Date()),
        "meals": [
            [
                "name": "Breakfast",
                "foodItems": [
                    [
                        "name": "Eggs",
                        "calories": 200,
                        "protein": 20,
                        "carbs": 2,
                        "fats": 15,
                        "servingSize": "2 eggs",
                        "servingWeight": 100
                    ],
                    [
                        "name": "Toast",
                        "calories": 150,
                        "protein": 5,
                        "carbs": 30,
                        "fats": 2,
                        "servingSize": "1 slice",
                        "servingWeight": 50
                    ]
                ]
            ]
        ],
        "totalCaloriesOverride": 1000
    ]

 
    if let userID = Auth.auth().currentUser?.uid {
       
        db.collection("users").document(userID).collection("dailyLogs").addDocument(data: dailyLog) { error in
            if let error = error {
                print("Error adding document: \(error.localizedDescription)")
            } else {
                print("Document added successfully!")
            }
        }
    } else {
        print("User ID not found")
    }
}
