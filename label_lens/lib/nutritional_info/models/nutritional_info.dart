class NutritionProduct {
  final String rawText;
  final String productName;
  final String? servingSize;
  final String? calories;
  final String? carbohydrates;
  final String? protein;
  final String? totalFat;
  final String? saturatedFat;
  final String? transFat;
  final String? fiber;
  final String? sodium;

  NutritionProduct({
    required this.rawText,
    required this.productName,
    this.servingSize,
    this.calories,
    this.carbohydrates,
    this.protein,
    this.totalFat,
    this.saturatedFat,
    this.transFat,
    this.fiber,
    this.sodium,
  });
}