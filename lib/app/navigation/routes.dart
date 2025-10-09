enum AppRoute {
  splash('/splash'),
  onboarding('/onboarding'),
  authWelcome('/auth'),
  questionnaire('/questionnaire'),
  home('/'),
  explore('/explore'),
  library('/library'),
  account('/account'),
  chat('/chat'),
  studySetDetail('/study-set/:id'),
  scanPreview('/scan/preview/:id'),
  scanOcr('/scan/ocr/:id'),
  scanActionChooser('/scan/action/:id'),
  scanGenerationReview('/scan/review/:id/:type');

  const AppRoute(this.path);

  final String path;
}
