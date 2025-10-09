import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../app/navigation/routes.dart';
import '../../../ui/theme/color_tokens.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<OnboardingPage> _pages = [
    OnboardingPage(
      title: 'Welcome to Studyly - Your\nAI Study Helper!',
      description:
          'Whether you\'re preparing for exams, learn new concepts, or just staying organized, Studyly creates a personalized roadmap to success.',
      image: Icons.home_outlined,
    ),
    OnboardingPage(
      title: 'Explore Diverse Study\nMaterials',
      description:
          'Access a vast library of study sets, flashcards, explanations, & practice questions. Discover materials across various subjects.',
      image: Icons.search,
    ),
    OnboardingPage(
      title: 'AI-Powered Learning\nAssistant',
      description:
          'Meet StudyBot, your AI learning assistant. Get instant help with tough questions, personalized study tips, and adaptive learning support.',
      image: Icons.chat_bubble_outline,
    ),
  ];

  void _nextPage() {
    if (_currentPage < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      context.go(AppRoute.authWelcome.path);
    }
  }

  void _skip() {
    context.go(AppRoute.authWelcome.path);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Phone Mockup Area
            Expanded(
              flex: 3,
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (index) {
                  setState(() {
                    _currentPage = index;
                  });
                },
                itemCount: _pages.length,
                itemBuilder: (context, index) {
                  return _PhoneMockup(page: _pages[index]);
                },
              ),
            ),

            // Content Area
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  children: [
                    const SizedBox(height: 24),
                    Text(
                      _pages[_currentPage].title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _pages[_currentPage].description,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 15,
                        color: Colors.black54,
                        height: 1.5,
                      ),
                    ),
                    const Spacer(),

                    // Page Indicator
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        _pages.length,
                        (index) => Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: _currentPage == index ? 24 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: _currentPage == index
                                ? StudyColors.primary
                                : Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Buttons
                    Row(
                      children: [
                        if (_currentPage < _pages.length - 1)
                          TextButton(
                            onPressed: _skip,
                            child: const Text(
                              'Skip',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.black54,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          )
                        else
                          const SizedBox(width: 80),
                        const Spacer(),
                        SizedBox(
                          width: 200,
                          height: 56,
                          child: ElevatedButton(
                            onPressed: _nextPage,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: StudyColors.primary,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(28),
                              ),
                            ),
                            child: Text(
                              _currentPage < _pages.length - 1
                                  ? 'Continue'
                                  : 'Let\'s Get Started',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }
}

class OnboardingPage {
  final String title;
  final String description;
  final IconData image;

  OnboardingPage({
    required this.title,
    required this.description,
    required this.image,
  });
}

class _PhoneMockup extends StatelessWidget {
  const _PhoneMockup({required this.page});

  final OnboardingPage page;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 280,
        height: 560,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(40),
          border: Border.all(color: Colors.black, width: 8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: Column(
            children: [
              // Status bar area
              Container(
                height: 40,
                color: StudyColors.background,
                child: Stack(
                  children: [
                    const Center(
                      child: Text(
                        '9:41',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Positioned(
                      right: 20,
                      top: 12,
                      child: Row(
                        children: const [
                          Icon(Icons.signal_cellular_4_bar, size: 16),
                          SizedBox(width: 4),
                          Icon(Icons.wifi, size: 16),
                          SizedBox(width: 4),
                          Icon(Icons.battery_full, size: 16),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Content based on page
              Expanded(
                child: Container(
                  color: StudyColors.background,
                  child: _buildPageContent(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPageContent() {
    if (page.image == Icons.home_outlined) {
      return _buildHomePage();
    } else if (page.image == Icons.search) {
      return _buildExplorePage();
    } else {
      return _buildChatPage();
    }
  }

  Widget _buildHomePage() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.psychology,
                  size: 20,
                  color: StudyColors.primary,
                ),
              ),
              const Expanded(
                child: Center(
                  child: Text(
                    'Explore',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const Icon(Icons.menu, size: 20),
            ],
          ),
          const SizedBox(height: 16),

          // Premium Card
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF4DB6AC), Color(0xFF80CBC4)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Upgrade Premium!',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Enjoy all the benefits',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'Upgrade',
                          style: TextStyle(
                            color: StudyColors.primary,
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Text('👑', style: TextStyle(fontSize: 40)),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Recent Study Sets
          const Text(
            'Recent Study Sets',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: const Border(
                left: BorderSide(color: StudyColors.progressGreen, width: 3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Cell Biology',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Container(
                      width: 32,
                      height: 32,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 32,
                            height: 32,
                            child: CircularProgressIndicator(
                              value: 0.58,
                              strokeWidth: 3,
                              backgroundColor: Colors.grey.shade200,
                              valueColor: const AlwaysStoppedAnimation(
                                StudyColors.progressGreen,
                              ),
                            ),
                          ),
                          const Text(
                            '58%',
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  '45 flashcards  ·  12 explanations  ·  20 exercises',
                  style: TextStyle(fontSize: 9, color: Colors.black54),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Calendar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildDateItem('19', 'Thu', false),
              _buildDateItem('20', 'Fri', false),
              _buildDateItem('21', 'Sat', false),
              _buildDateItem('22', 'Sun', true),
              _buildDateItem('23', 'Mon', false),
            ],
          ),
          const SizedBox(height: 12),

          // Study Plan
          const Text(
            '← study plan today (1/5)',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildDateItem(String day, String label, bool isToday) {
    return Column(
      children: [
        Text(
          day,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: isToday ? Colors.black : Colors.black54,
          ),
        ),
        Text(label, style: const TextStyle(fontSize: 9, color: Colors.black54)),
        const SizedBox(height: 2),
        if (isToday)
          Container(width: 16, height: 2, color: StudyColors.primary),
      ],
    );
  }

  Widget _buildExplorePage() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.psychology,
                  size: 20,
                  color: StudyColors.primary,
                ),
              ),
              const Expanded(
                child: Center(
                  child: Text(
                    'Explore',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const Icon(Icons.search, size: 20),
            ],
          ),
          const SizedBox(height: 16),

          // Tabs
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildTab('Study Sets', true),
                const SizedBox(width: 8),
                _buildTab('Flashcards', false),
                const SizedBox(width: 8),
                _buildTab('Explanations', false),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Study Cards
          Expanded(
            child: ListView(
              children: [
                _buildStudyCard(
                  'Microbiology',
                  '246 flashcards · 155 explanations · 120 exercises',
                  '🧬',
                  'Community',
                  const Color(0xFF42A5F5),
                ),
                const SizedBox(height: 12),
                _buildStudyCard(
                  'Artificial Intelligence',
                  '324 flashcards · 214 explanations · 50 exercises',
                  '🤖',
                  'Community',
                  const Color(0xFFAB47BC),
                ),
                const SizedBox(height: 12),
                _buildStudyCard(
                  'Entrepreneurship',
                  '250 flashcards · 154 explanations · 102 exercises',
                  '💼',
                  'Community',
                  const Color(0xFF66BB6A),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTab(String label, bool isSelected) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isSelected ? StudyColors.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: isSelected ? Colors.white : Colors.black54,
        ),
      ),
    );
  }

  Widget _buildStudyCard(
    String title,
    String subtitle,
    String emoji,
    String tag,
    Color borderColor,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: borderColor, width: 3)),
      ),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 9, color: Colors.black54),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.group,
                            size: 10,
                            color: Colors.black54,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            tag,
                            style: const TextStyle(
                              fontSize: 9,
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    const Text(
                      '20:36',
                      style: TextStyle(fontSize: 9, color: Colors.black54),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.play_circle_outline,
                      size: 16,
                      color: Colors.black54,
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.more_vert,
                      size: 16,
                      color: Colors.black54,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatPage() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Header
          Row(
            children: const [
              Icon(Icons.arrow_back, size: 20),
              Expanded(
                child: Center(
                  child: Text(
                    'Chat with StudyBot',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              Icon(Icons.more_vert, size: 20),
            ],
          ),
          const SizedBox(height: 24),

          // Chat Message
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Hello! How can I assist you with your studies today?',
                  style: TextStyle(fontSize: 12, height: 1.4),
                ),
                const SizedBox(height: 8),
                Row(
                  children: const [
                    Icon(
                      Icons.thumb_up_outlined,
                      size: 14,
                      color: Colors.black54,
                    ),
                    SizedBox(width: 12),
                    Icon(
                      Icons.thumb_down_outlined,
                      size: 14,
                      color: Colors.black54,
                    ),
                    SizedBox(width: 12),
                    Icon(Icons.copy_outlined, size: 14, color: Colors.black54),
                    SizedBox(width: 12),
                    Icon(Icons.share_outlined, size: 14, color: Colors.black54),
                    SizedBox(width: 12),
                    Icon(
                      Icons.refresh_outlined,
                      size: 14,
                      color: Colors.black54,
                    ),
                    SizedBox(width: 12),
                    Icon(Icons.flag_outlined, size: 14, color: Colors.black54),
                  ],
                ),
              ],
            ),
          ),
          const Spacer(),

          // User message
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: StudyColors.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'What is meant by Mitosis?',
                style: TextStyle(fontSize: 12, color: Colors.white),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Input
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'What is meant by Mitosis?',
                    style: TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  color: StudyColors.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.send, size: 16, color: Colors.white),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
