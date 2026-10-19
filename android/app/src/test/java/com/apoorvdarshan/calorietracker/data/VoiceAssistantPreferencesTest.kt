package com.apoorvdarshan.calorietracker.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class VoiceAssistantPreferencesTest {
    @Test
    fun repliesInTheAppLanguageUntilTheUserPicksAnother() {
        assertEquals(VoiceAssistantPreferences.LANGUAGE_APP, VoiceAssistantPreferences().language)
    }

    @Test
    fun autoCaptureStartsOn() {
        assertTrue(VoiceAssistantPreferences().autoCapture)
    }
}
