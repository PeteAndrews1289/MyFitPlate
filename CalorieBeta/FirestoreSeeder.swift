
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
                AppLog.data.error("Failed to add sample log: \(error.localizedDescription, privacy: .public)")
            } else {
                AppLog.data.info("Sample log added successfully.")
            }
        }
    } else {
        AppLog.data.warning("Cannot add sample log because no user is signed in.")
    }
}
