enum AppRoute {
  splash('/splash'),
  onboarding('/onboarding'),
  authWelcome('/auth'),
  questionnaire('/questionnaire'),
  home('/'),
  library('/library'),
  account('/account'),
  chat('/chat'),
  studySetDetail('/study-set/:id'),
  studySetCreate('/study-set/create'),
  flashcardReview('/study-set/:id/review'),
  flashcardCreate('/study-set/:id/flashcard/create'),
  scanPreview('/scan/preview/:id'),
  scanOcr('/scan/ocr/:id'),
  scanActionChooser('/scan/action/:id'),
  scanGenerationReview('/scan/review/:id/:type');

  const AppRoute(this.path);

  final String path;
}
