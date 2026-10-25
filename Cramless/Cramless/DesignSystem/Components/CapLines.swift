import Foundation

// What Cap says when he is tapped. Short, warm and a little silly, in his voice (docs/design.md ▸ Voice): never a guilt trip,
// never a nudge about what you haven't done, no emoji. A pose's own lines say what he is doing in it; the general lines work
// anywhere; the time-of-day lines greet the hour; the flustered ones are for being tapped again and again; the refreshed ones are
// for when the sky has been pulled down and refreshed.
//
// There are plenty of each so a line doesn't come back soon: `CapLineBag` deals them out without repeating until a pool has
// been used up (`CapSpeech.swift`). Copy is localizable like the rest of the app, one key per line. Keep each under about 40
// characters: the bubble is two lines at most.

enum CapLines {
    static func lines(for pose: CapPose) -> [LocalizedStringResource] {
        switch pose {
        case .wave: wave
        case .study: study
        case .celebrate: celebrate
        case .sleep: sleep
        case .think: think
        case .point: point
        case .scan: scan
        case .plan: plan
        case .mic: mic
        case .relax: relax
        case .nice: nice
        case .almost: almost
        case .notYet: notYet
        case .listen: listen
        case .ask: ask
        case .sleepy: sleepy
        case .proud: proud
        case .stargaze: stargaze
        case .tuckIn: tuckIn
        }
    }

    // MARK: A pose's own

    static let wave: [LocalizedStringResource] = [
        "Hi again!", "Oh, hello there.", "Wave back? I'll wait.", "You came back. Love that.", "High paw!",
        "Heya, scholar.", "Look who it is.", "Waving is my cardio.", "I practised that wave.", "Paw up, spirits up.",
        "Hello, hello, hello.", "Nice to see you.", "Hi! Still me. Still Cap.", "That's a friendly tap.",
        "Wave received. Reply sent.", "Come on in, the studying's fine.", "Good to have you here.",
        "I'd high-five you. Paws, though.",
    ]

    static let study: [LocalizedStringResource] = [
        "Shh. Good part coming up.", "Page 42. Riveting.", "I'm reading. Fascinating.", "One more card?",
        "Cards make me smarter, slowly.", "I read that twice. It stuck.", "Brain snack time.", "Spaced repetition. Trust it.",
        "Quiet, scholar at work.", "Boop noted. Back to reading.", "This one's a classic.", "I've met this card before.",
        "Reading is brain gym.", "Never leave home without a highlighter.", "Learning it a little at a time.",
        "Want to quiz me? I dare you.", "Fun fact: books don't bite.", "Turning pages, turning heads.",
    ]

    static let celebrate: [LocalizedStringResource] = [
        "Woohoo!", "Again! Again!", "Confetti is free. Take some.", "We did it!", "Party in the pond!",
        "I can't stop smiling.", "That's the spirit!", "Pop the confetti!", "Joy, delivered.", "Best tap ever.",
        "Tell the ducks. They'll cheer.", "I'd cartwheel. Rodent physics.", "Cheers, scholar!", "More sparkle, please.",
        "Hip hip, hooray!", "I danced. You saw it.", "Happiness level: capybara.", "Feeling unstoppable.",
    ]

    static let sleep: [LocalizedStringResource] = [
        "Five more minutes…", "Zzz… oh! Hi.", "I wasn't sleeping. Resting my eyes.", "Mmm… oranges…",
        "Don't wake the capybara.", "Dreaming of study snacks.", "Nap loading… 87%.", "Shh. The cards are asleep too.",
        "Zzzoom.", "I can sleep in water, you know.", "Cards make good pillows.", "Sleep helps memory stick.",
        "Just resting my brain.", "Wake me at the good part.", "Mmf. Is it snack time?", "Soft cards, soft dreams.",
        "Too cozy to move.", "Rest is part of studying.",
    ]

    static let think: [LocalizedStringResource] = [
        "Hmm. Interesting.", "It's on the tip of my snout.", "Thinking… thinking…", "Let me chew on that.",
        "Ooh, I almost have it.", "Big thoughts incoming.", "My brain is buffering.", "Give me a second. Or ten.",
        "Hmm, what links to what?", "Wait… I know this.", "Good questions make good answers.", "Chin-scratch mode: on.",
        "Pondering. Quietly.", "Let's figure it out together.", "The answer's in there somewhere.",
        "Thinking is half the work.", "Hold on, connecting dots.", "Aha… no. Hold on.",
    ]

    static let point: [LocalizedStringResource] = [
        "Look right there.", "That's the one!", "See that card? Yep.", "Pointing is polite.", "This part matters.",
        "Right here, friend.", "That one's worth a look.", "Eyes on the card!", "It says it right there.", "Spot the clue.",
        "Point taken.", "I'd point twice if I could.", "Behold: a card.", "Here's the answer, served.", "Follow my paw.",
        "Found it for you.", "A gentle nudge: that one.", "Pointing, but kindly.",
    ]

    static let scan: [LocalizedStringResource] = [
        "Say cheese, textbook.", "Click! Got the page.", "Photo day for your notes.", "Hold still, paragraph.",
        "I'm a great photographer.", "Scan complete. Probably.", "Pages in, questions out.", "Smile for the camera!",
        "Flash! Did I get it?", "Nothing escapes my lens.", "Textbooks, meet my phone.", "Capturing knowledge…",
        "Snap, snap, study.", "Notes: photographed. Nice.", "Camera paws: ready.", "This page photographs well.",
        "Got the whole spread.", "Click-click, easy.",
    ]

    static let plan: [LocalizedStringResource] = [
        "A plan! I love a plan.", "Calendar looking good.", "Little by little, it adds up.", "Checkmarks are my favourite.",
        "Tomorrow-us will be ready.", "Short sessions win.", "Slow and steady, like me.", "Today: a tiny bit. Perfect.",
        "Plans make exams friendlier.", "Let's colour in the calendar.", "Every square counts.", "No rush. Just rhythm.",
        "Look at those checkmarks.", "Future you says thanks.", "Small steps. Big sky.", "I've pencilled in a nap, too.",
        "We've got this scheduled.", "A little every day.",
    ]

    static let mic: [LocalizedStringResource] = [
        "Check, check, one two.", "Is this thing on?", "Testing, testing. Hi.", "I could host a podcast.",
        "Mic drop? Gently.", "Lecture time. I'm all ears.", "Say something smart.", "Recording… recording…",
        "Speak up, I'm listening.", "My voice is mostly hums.", "Sound check: lovely.", "Ooh, nice acoustics.",
        "I'll catch every word.", "Talk to me.", "Good audio, good notes.", "Hum hum. Okay, ready.",
        "Feedback? Only the nice kind.", "Live from the pond.",
    ]

    static let relax: [LocalizedStringResource] = [
        "Ahh. Tea time.", "Nothing due. Bliss.", "Sip, sigh, repeat.", "This beanbag is my home.", "Rest counts as progress.",
        "Peak relaxation achieved.", "Hot drink, cool capybara.", "Mmm, still warm.", "You earned a break, too.",
        "Slow day, good day.", "Even brains need breaks.", "Just vibing. And sipping.", "Come sit. There's room.",
        "Steam is a great view.", "Soaking in the quiet.", "No stress. Only tea.", "Spa day, capybara style.",
        "I'm not lazy. I'm recharging.",
    ]

    static let nice: [LocalizedStringResource] = [
        "Yes! Nailed it.", "That was a good one.", "Fist bump? Okay, paw bump.", "Look at you go!", "Smooth.",
        "Chef's kiss. Capybara edition.", "Boom.", "Right on the money.", "You're on a roll.", "My favourite kind of answer.",
        "Brain: 1. Doubt: 0.", "That one stuck. Nice.", "Show-off. I like it.", "Pure skill.", "That's how it's done.",
        "I knew you'd get it.", "Another one for the sky.", "Strong work, scholar.",
    ]

    static let almost: [LocalizedStringResource] = [
        "So close!", "Nearly there. Keep going.", "You're warm. Really warm.", "One tiny tweak.",
        "Almost counts for something.", "I can see it from here.", "Just a hair away.", "Good thinking. Polish it.",
        "That's most of it.", "Ooh, nearly.", "Tilt your head, try again.", "Close enough to smell it.",
        "You've basically got it.", "Nudge it a little more.", "Good instincts. Keep them.", "Nearly. Which part's missing?",
        "Almost is how learning looks.", "Another go? You're close.",
    ]

    static let notYet: [LocalizedStringResource] = [
        "Not yet. That's fine.", "Everyone starts somewhere.", "It'll click. Promise.", "Let's read it once more.",
        "No rush. I'm patient.", "Not yet just means not yet.", "Mistakes are free here.", "We'll circle back to it.",
        "Tough one. You'll get it.", "I'll sit with you.", "Learning is just practising.", "That card will be back.",
        "Breathe. Then again.", "Little by little.", "Still learning, still good.", "Even I forget things.",
        "A soft landing. Try again.", "We've got time.",
    ]

    static let listen: [LocalizedStringResource] = [
        "Go on, I'm writing it down.", "Mm-hm. Mm-hm.", "Taking notes. Carry on.", "Ooh, that's a good point.",
        "Say it in your own words.", "I'm all ears. Big ears.", "Scribble, scribble.", "Explain it to me.",
        "Tell me everything.", "Teaching is the best test.", "I'll ask a question after.", "Take your time.",
        "Notepad ready. Pencil sharp.", "I won't interrupt. Much.", "Keep going, it's good.",
        "I'm listening with my whole face.", "Got it. Got it. Got it.", "Pretend I'm your class.",
    ]

    static let ask: [LocalizedStringResource] = [
        "Ooh! Ooh! I have a question.", "Pick me!", "Quick question…", "What if…?", "Can I ask something?",
        "Curiosity: loading.", "Hand up, as usual.", "Why? Always why.", "There are no silly questions.",
        "Questions are my snacks.", "Let's find out together.", "I wonder…", "Ask me anything, too.", "Tell me more, please.",
        "Raise your paw if you wonder.", "I love a good why.", "Hmm, but how?", "Curious capybara, reporting.",
    ]

    static let sleepy: [LocalizedStringResource] = [
        "Yaaawn… sorry.", "Is it bedtime?", "My eyelids filed a complaint.", "Just five more cards…",
        "Sleepy, but here.", "A short study, then a nap.", "Mmf. Pardon me.", "Warm blanket thoughts.",
        "Yawns are contagious. You're welcome.", "Dim the lights, please.", "I'm not tired. Yaaawn.", "Almost nap o'clock.",
        "Heavy eyelids, light heart.", "Even a tiny session counts.", "The pillow's calling. Soon.", "Cozy mode: activated.",
        "A yawn is a good stretch.", "Rest up, scholar.",
    ]

    static let proud: [LocalizedStringResource] = [
        "Look at that star.", "I'm so proud of you.", "Chest out. Tail… well, no tail.", "You did that.",
        "Shiny star, shiny scholar.", "Very proud. Very capybara.", "Another one for the books.", "Look how far you've come.",
        "That glint? It's you.", "Proud paws on hips.", "Take a bow. I'll clap.", "Not bad, scholar.",
        "Heroes wear mortarboards.", "Gold star, well deserved.", "I'd frame this moment.", "Quietly beaming.",
        "Be proud. I am.", "Good effort adds up.",
    ]

    static let stargaze: [LocalizedStringResource] = [
        "That one's a memory. See it?", "Look, it's twinkling.", "The dim ones like a visit.", "I found a bright one!",
        "Every star is something you know.", "Telescope time.", "Each star is a thing you learned.", "Ooh, what's that one?",
        "Night shift: stargazing.", "Counting stars, one by one.", "The sky looks lovely tonight.", "A little polish, and it shines.",
        "I could watch this all night.", "Quiet sky, quiet mind.", "Careful, that's a big one.", "Make a wish. Then a review.",
        "Constellation spotted.", "Even the dim ones are yours.",
    ]

    static let tuckIn: [LocalizedStringResource] = [
        "Tucking in the stars.", "Goodnight, little cards.", "Cozy blanket, cozy brain.", "Sleep tight, memories.",
        "Shh. They're drifting off.", "Pat, pat. Snug.", "Sleep is studying, too.", "Sweet dreams, scholar.",
        "Tomorrow's brain says thanks.", "All tucked in. Nicely done.", "A blanket full of stars.", "Goodnight, goodnight.",
        "Your cards are safe with me.", "Rest now. Remember later.", "Smoothing the corners.", "A cozy end to a good day.",
        "Dream of oranges.", "Lights low. You did enough.",
    ]

    // MARK: Anywhere

    static let general: [LocalizedStringResource] = [
        "Boop!", "Hehe, that tickles.", "You tapped me. I felt it.", "Hello from a capybara.", "Fun fact: I'm a rodent.",
        "I'm the biggest rodent. No big deal.", "Fun fact: my teeth never stop growing.", "Fun fact: capybaras nap in water.",
        "Capybaras hum when they're happy.", "I love oranges. Just saying.", "Webbed feet. Excellent swimmer.",
        "Oranges are my study snack.", "Ducks like me. Long story.", "You're doing great, you know.",
        "Be kind to your brain today.", "Drink some water. I'd know.", "Posture check, scholar.", "Stretch break? Paws up!",
        "Little and often beats lots and rarely.", "Forgetting is normal. Reviewing helps.", "Try explaining it out loud.",
        "Eyes on the prize. Gently.", "I believe in you. A lot.", "Tap me anytime.", "Poke me again. I like it.",
        "You're my favourite human.", "Capybaras are very chill. I'm very chill.", "I give great hugs. Short arms.",
        "No pressure. Just vibes.", "A tiny step is still a step.", "Learn a little, rest a little.", "I'm rooting for you.",
        "Whatever happens, I'm here.", "Small wins add up.", "Take a breath. Smile. Continue.", "Hydration station: you.",
        "Remember: it's a marathon.", "Study buddy, reporting for duty.", "Gentle reminder: you're great.",
        "My hat stays on. Always.",
    ]

    // MARK: By the hour

    static let morning: [LocalizedStringResource] = [
        "Good morning, scholar.", "Morning! Orange juice?", "Fresh brain, fresh start.", "The early bird gets the cards.",
        "Rise and review.", "Sunrise study? Lovely.",
    ]

    static let afternoon: [LocalizedStringResource] = [
        "Good afternoon!", "Lunch for the brain?", "Afternoon slump? Stretch.", "Sun's high, brain's warm.",
        "A perfect time for a few cards.", "Halfway through the day. Nice.",
    ]

    static let evening: [LocalizedStringResource] = [
        "Good evening.", "Golden hour, golden brain.", "A wind-down review, anyone?", "Cozy evening, cozy cards.",
        "Food for thought.", "The day's nearly done.",
    ]

    static let night: [LocalizedStringResource] = [
        "Still up? Me too.", "Night owl, capybara edition.", "A late-night brain is a sleepy one.", "The stars are out. Look!",
        "A tiny review, then bed.", "Sleep soon. Memories need it.",
    ]

    // MARK: Tapped again and again

    static let flustered: [LocalizedStringResource] = [
        "Whoa, easy there!", "Tap tap tap!", "I'm ticklish, you know.", "Okay okay, I'm awake!", "Boop count: lots.",
        "You found my ticklish spot.", "Hehe, stop! No, don't.", "I'm getting dizzy.", "Is this a game? I love it.",
        "Capybara overload.", "That's a lot of boops.", "Pace yourself, scholar.",
    ]

    // MARK: When the sky is refreshed

    /// What he says when the sky has been pulled down and refreshed: it is up to date, and he is pleased about it.
    static let refreshed: [LocalizedStringResource] = [
        "Fresh sky. Lovely.", "All up to date.", "Looked again. All good.", "Sky's current. Gold star.",
        "There. Everything's current.", "One fresh sky, as ordered.", "Stars checked, every one.",
        "Same you, brand new view.", "That's the latest.", "Nice pull. Sky refreshed.", "Fresh as a pond at dawn.",
        "I counted again. Still great.", "Up to date. Nice.", "The sky says hello.",
    ]
}
