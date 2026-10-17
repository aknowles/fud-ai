package com.apoorvdarshan.calorietracker.services.ai

import com.apoorvdarshan.calorietracker.models.AIProvider
import org.junit.Assert.assertEquals
import org.junit.Test

class OpenAITokenLimitParameterTest {
    @Test
    fun customGpt6ModelsUseCompletionTokenLimit() {
        listOf(
            "gpt-6",
            "gpt-6-sol",
            "gpt-6-astra",
            "gpt-6.1-sol",
            "openai/gpt-6-sol",
            "gateway/openai/gpt-6-astra",
            "  OpenAI/GPT-6.1-SOL  "
        ).forEach { model ->
            assertEquals(
                model,
                "max_completion_tokens",
                OpenAICompatibleClient.tokenLimitParameter(AIProvider.CUSTOM_OPENAI, model)
            )
        }
    }

    @Test
    fun customLegacyAndOtherModelsKeepTheirTokenLimitParameter() {
        listOf("gpt-5.6-sol", "openai/o1-mini", "o3", "o4-mini").forEach { model ->
            assertEquals(
                model,
                "max_completion_tokens",
                OpenAICompatibleClient.tokenLimitParameter(AIProvider.CUSTOM_OPENAI, model)
            )
        }
        listOf("gpt-4.1", "openai/gpt-4o-mini", "qwen/qwen3.8", "", "   ").forEach { model ->
            assertEquals(
                model,
                "max_tokens",
                OpenAICompatibleClient.tokenLimitParameter(AIProvider.CUSTOM_OPENAI, model)
            )
        }
    }

    @Test
    fun gpt6DetectionDoesNotChangeOtherProviderTokenLimits() {
        AIProvider.values().forEach { provider ->
            listOf("gpt-6-sol", "openai/gpt-6-astra").forEach { model ->
                val expected = if (provider == AIProvider.OPENAI || provider == AIProvider.CUSTOM_OPENAI) {
                    "max_completion_tokens"
                } else {
                    "max_tokens"
                }
                assertEquals(
                    "$provider: $model",
                    expected,
                    OpenAICompatibleClient.tokenLimitParameter(provider, model)
                )
            }
        }
    }
}
