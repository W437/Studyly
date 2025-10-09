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
  studySetDetail('/study-set/:id');

  const AppRoute(this.path);

  final String path;
}
