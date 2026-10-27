import AVFoundation
import SwiftUI

/// Settings → App Settings → Coach Personality (also linked from Voice Assistant settings).
struct CoachPersonalityView: View {
    @AppStorage(CoachStyle.personalityKey) private var personalityRaw = CoachPersonality.standard.rawValue
    @AppStorage(CoachStyle.intensityKey) private var intensityRaw = CoachIntensity.normal.rawValue
    @AppStorage(CoachStyle.customStyleKey) private var customStyle = ""
    @State private var voicesApplied = false
    @State private var speaker = AVSpeechSynthesizer()

    private var personality: CoachPersonality { CoachPersonality(rawValue: personalityRaw) ?? .standard }

    var body: some View {
        Form {
            Section {
                ForEach(CoachPersonality.allCases) { option in
                    Button {
                        personalityRaw = option.rawValue
                        voicesApplied = false
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: option == personality ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(option == personality ? AppColors.calorie : Color.secondary)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(option.displayName)
                                    .font(.system(.body, design: .rounded, weight: .medium))
                                    .foregroundStyle(.primary)
                                Text("“\(option.sample)”")
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Personality")
            } footer: {
                Text("Tone only. Numbers, health and medicine guidance and safety advice stay the same in every style, and Coach drops the act if you seem upset.")
            }

            if personality == .custom {
                Section("Your style") {
                    TextField("e.g. Talk like a laid-back surfer who loves vegetables", text: $customStyle, axis: .vertical)
                        .lineLimit(2...5)
                }
            }

            if personality != .standard {
                Section {
                    Picker("Intensity", selection: $intensityRaw) {
                        ForEach(CoachIntensity.allCases) { Text($0.displayName).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    Button {
                        speak(personality.sample)
                    } label: {
                        Label("Hear a sample", systemImage: "speaker.wave.2.fill")
                    }
                } footer: {
                    Text("The sample uses the phone's voice; the voice assistant uses the voice below.")
                }
            }

            if !personality.suggestedVoices.isEmpty {
                Section {
                    ForEach(personality.suggestedVoices.sorted(by: { $0.key.rawValue < $1.key.rawValue }), id: \.key) { provider, voice in
                        LabeledContent(provider == .gemini ? "Gemini" : "OpenAI", value: voice)
                    }
                    Button(voicesApplied ? String(localized: "Voices set") : String(localized: "Use these voices")) {
                        CoachStyle.applySuggestedVoices(for: personality)
                        voicesApplied = true
                    }
                    .disabled(voicesApplied)
                } header: {
                    Text("Suggested voice")
                } footer: {
                    Text("Pick any voice for each provider in Settings → Voice Assistant.")
                }
            }
        }
        .navigationTitle("Coach Personality")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { speaker.stopSpeaking(at: .immediate) }
    }

    private func speak(_ text: String) {
        speaker.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = personality == .calm ? 0.42 : (personality == .drillSergeant ? 0.56 : 0.5)
        utterance.pitchMultiplier = personality == .playful ? 0.9 : 1
        speaker.speak(utterance)
    }
}
