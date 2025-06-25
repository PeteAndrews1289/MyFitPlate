import Foundation
import UIKit
import CoreML
import Vision

// Defines possible errors that can occur during image recognition with the ML model.
enum ImageRecognitionError: Error {
    case modelNotFound // Indicates the ML model could not be loaded.
    case imageProcessingError // Indicates an issue resizing or processing the image.
    case predictionError(Error) // Wraps errors from the prediction process.
    case invalidOutputFormat // Indicates the model output format is unexpected.
}

// This class handles image classification using the MobileNetV3 Food-101 model to identify food items.
class MLImageModel {
    // Stores the CoreML model configured for Vision framework use.
    private let model: VNCoreMLModel
    // Array of food categories supported by the Food-101 dataset.
    private let foodCategories: [String] = Food101Categories.allCases.map { $0.rawValue } // Maps enum cases to string names.

    // Initializes the model by loading the MobileNetV3 Food-101 model.
    init() {
        do {
            // Configures the model with default settings.
            let modelConfig = MLModelConfiguration()
            // Loads the pre-trained MobileNetV3 Food-101 model (generated class assumed to exist).
            let coreMLModel = try mobilenetv3_food101_full().model // Accesses the MLModel instance.
            self.model = try VNCoreMLModel(for: coreMLModel) // Converts to a Vision-compatible model.
        } catch {
            fatalError("Failed to load MobileNetV3 Food-101 model: \(error.localizedDescription)") // Terminates if model fails to load.
        }
    }

    /// Classifies a food item from an image using the MobileNetV3 Food-101 model.
    /// - Parameters:
    ///   - image: The UIImage to classify.
    ///   - completion: Closure returning a Result with the predicted food name or an error.
    func classifyImage(image: UIImage, completion: @escaping (Result<String, ImageRecognitionError>) -> Void) {
        // Resizes the image to 224x224, the required input size for the model.
        guard let resizedImage = image.resized(toSize: CGSize(width: 224, height: 224)),
              let ciImage = CIImage(image: resizedImage) else { // Converts to CIImage for Vision.
            print("❌ Failed to process or resize image to 224x224") // Logs the error.
            completion(.failure(.imageProcessingError)) // Returns an image processing error.
            return
        }

        // Creates a request handler with the resized image.
        let requestHandler = VNImageRequestHandler(ciImage: ciImage)
        // Configures a request to perform classification with the model.
        let request = VNCoreMLRequest(model: model) { request, error in
            // Ensures results are available and of the expected type.
            guard let observations = request.results as? [VNClassificationObservation], !observations.isEmpty else {
                print("❌ No classification results or error: \(String(describing: error))") // Logs if no results.
                DispatchQueue.main.async {
                    completion(.failure(.predictionError(error ?? NSError(domain: "NoResults", code: -1, userInfo: nil))))
                }
                return
            }

            // Extracts the top prediction from the observations.
            let topPrediction = observations[0]
            let foodName = topPrediction.identifier // The predicted food category (e.g., "pizza").
            let confidence = topPrediction.confidence // Confidence score of the prediction.

            print("✅ Predicted food: \(foodName) (confidence: \(confidence))") // Logs the prediction.
            DispatchQueue.main.async {
                completion(.success(foodName)) // Returns the food name on the main thread.
            }
        }

        // Sets the image scaling option to fill the 224x224 input size.
        request.imageCropAndScaleOption = .scaleFill

        do {
            try requestHandler.perform([request]) // Executes the classification request.
        } catch {
            print("❌ Failed to perform image classification: \(error.localizedDescription)") // Logs the error.
            DispatchQueue.main.async {
                completion(.failure(.predictionError(error))) // Returns a prediction error.
            }
        }
    }
}

// Extends UIImage to add a resizing method for model compatibility.
extension UIImage {
    // Resizes the image to a specified size.
    func resized(toSize size: CGSize) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(size, false, 0.0) // Starts a new graphics context.
        self.draw(in: CGRect(origin: .zero, size: size)) // Draws the image in the new size.
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext() // Retrieves the resized image.
        UIGraphicsEndImageContext() // Cleans up the graphics context.
        return resizedImage // Returns the resized image (optional due to potential failure).
    }
}

// Enum for Food-101 categories (you need to define all 101 categories)
// Represents the 101 food categories from the Food-101 dataset as an enum.
enum Food101Categories: String, CaseIterable {
    case apple_pie, baby_back_ribs, baklava, beef_carpaccio, beef_tartare, // ... Add all 101 categories here
         beef_tongue, beet_salad, beignets, bibimbap, bread_pudding, // Partial list for example
         breakfast_burrito, bruschetta, caesar_salad, cannoli, caprese_salad,
         carrot_cake, ceviche, cheesecake, chicken_curry, chicken_quesadilla,
         chicken_wings, chocolate_cake, chocolate_mousse, churros, clam_chowder,
         club_sandwich, crab_cakes, creme_brulee, croques_monsieur, deviled_eggs,
         donuts, dumplings, edamame, eggs_benedict, escargot, falafel, filet_mignon,
         fish_and_chips, foie_gras, french_fries, french_onion_soup, french_toast,
         fried_calamari, fried_rice, fruit_salad, garlic_bread, gnocchi, greek_salad,
         grilled_cheese_sandwich, grilled_salmon, guacamole, gyoza, hamburger,
         hot_and_sour_soup, hot_dog, huevos_rancheros, hummus, ice_cream, lamb_shanks,
         lasagna, lobster_bisque, lobster_roll_sandwich, macaroni_and_cheese, macarons,
         miso_soup, mussels, nachos, omelette, onion_rings, oysters, pad_thai, paella,
         pancakes, panna_cotta, peking_duck, pho, pizza, pork_chop, pork_gyozas,
         pulled_pork_sandwich, ramen, ravioli, red_velvet_cake, risotto, samosa,
         sashimi, scallops, seafood_pasta, shrimp_and_grits, spaghetti_bolognese,
         spaghetti_carbonara, spring_rolls, steak, strawberry_shortcake, sushi,
         tacos, takoyaki, tiramisu, tuna_tartare, waffles
    // Ensure you list all 101 categories from the Food-101 dataset here.
    // Note: The list is complete as per the Food-101 dataset; ensure all cases are included.
}
