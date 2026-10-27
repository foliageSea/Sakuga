package com.foliage.sakuga

import androidx.core.content.FileProvider

/** Separate provider class for reliable FileProvider initialization across devices. */
class ImageClipboardProvider : FileProvider()
