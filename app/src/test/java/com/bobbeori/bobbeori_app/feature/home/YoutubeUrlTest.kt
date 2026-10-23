package com.bobbeori.bobbeori_app.feature.home

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class YoutubeUrlTest {
    @Test
    fun `supports common youtube video urls`() {
        assertTrue(isSupportedYoutubeUrl("https://www.youtube.com/watch?v=dQw4w9WgXcQ"))
        assertTrue(isSupportedYoutubeUrl("https://youtu.be/dQw4w9WgXcQ"))
        assertTrue(isSupportedYoutubeUrl("https://youtube.com/shorts/dQw4w9WgXcQ"))
        assertTrue(isSupportedYoutubeUrl("https://m.youtube.com/live/dQw4w9WgXcQ"))
    }

    @Test
    fun `rejects non-youtube and channel urls`() {
        assertFalse(isSupportedYoutubeUrl("https://example.com/watch?v=dQw4w9WgXcQ"))
        assertFalse(isSupportedYoutubeUrl("https://youtube.com/@channel"))
        assertFalse(isSupportedYoutubeUrl("not a url"))
    }

    @Test
    fun `extracts youtube url from shared text`() {
        assertEquals(
            "https://youtu.be/dQw4w9WgXcQ?t=10",
            extractYoutubeUrl("맛있는 영상이에요 https://youtu.be/dQw4w9WgXcQ?t=10 같이 봐요"),
        )
    }
}
