package com.apoorvdarshan.calorietracker.ui.components

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraMetadata
import android.hardware.camera2.CaptureRequest
import android.hardware.camera2.CaptureResult
import android.hardware.camera2.TotalCaptureResult
import android.os.SystemClock
import androidx.camera.camera2.interop.Camera2CameraControl
import androidx.camera.camera2.interop.Camera2CameraInfo
import androidx.camera.camera2.interop.Camera2Interop
import androidx.camera.camera2.interop.CaptureRequestOptions
import androidx.camera.camera2.interop.ExperimentalCamera2Interop
import androidx.camera.core.Camera
import androidx.camera.core.CameraInfo
import androidx.camera.core.CameraSelector
import androidx.camera.core.FocusMeteringAction
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.LocalFlorist
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import com.apoorvdarshan.calorietracker.R
import com.apoorvdarshan.calorietracker.ui.theme.AppColors
import com.google.common.util.concurrent.ListenableFuture
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeoutOrNull
import kotlin.coroutines.resume
import kotlin.math.roundToInt

/** Focus support of a camera CameraX lists; no support when Camera2 details are unavailable. */
@androidx.annotation.OptIn(markerClass = [ExperimentalCamera2Interop::class])
internal fun focusCapabilities(info: CameraInfo): FocusCapabilities = runCatching {
    val camera2 = Camera2CameraInfo.from(info)
    FocusCapabilities.from(
        afModes = camera2.getCameraCharacteristic(CameraCharacteristics.CONTROL_AF_AVAILABLE_MODES),
        maxAfRegions = camera2.getCameraCharacteristic(CameraCharacteristics.CONTROL_MAX_REGIONS_AF),
        maxAeRegions = camera2.getCameraCharacteristic(CameraCharacteristics.CONTROL_MAX_REGIONS_AE),
        minimumFocusDiopters = camera2.getCameraCharacteristic(CameraCharacteristics.LENS_INFO_MINIMUM_FOCUS_DISTANCE),
    )
}.getOrDefault(FocusCapabilities.NONE)

/**
 * The camera [chooseCamera] picks among those CameraX can open, or null when none fits.
 * When CameraX lists nothing, the default back camera is tried so binding reports the error.
 */
internal fun ProcessCameraProvider.captureCameraSelector(allowFront: Boolean): CameraSelector? {
    val cameras = runCatching { availableCameraInfos }.getOrDefault(emptyList())
    if (cameras.isEmpty()) return CameraSelector.DEFAULT_BACK_CAMERA
    val options = cameras.map { info ->
        val lens = when (runCatching { info.lensFacing }.getOrNull()) {
            CameraSelector.LENS_FACING_BACK -> CaptureLens.BACK
            CameraSelector.LENS_FACING_FRONT -> CaptureLens.FRONT
            else -> null
        }
        CameraOption(lens, autofocus = focusCapabilities(info).autofocus)
    }
    return chooseCamera(options, allowFront)?.let { cameras[it].cameraSelector }
}

/**
 * Applies CameraFocusLogic to the camera a screen has bound:
 * - continuous autofocus stays CameraX's default (CONTINUOUS_PICTURE) while nothing is tapped;
 * - a tap focuses and exposes for that point, retries in the close-up (macro) range when the
 *   normal scan cannot focus, and holds until the phone is turned or moved, or a timeout;
 * - before a photo it lets focus settle and scans the middle of the frame when continuous
 *   autofocus gave up, so a close-up is not taken mid-hunt.
 * Fixed-focus cameras only expose for the tapped point; cameras without metering regions
 * ignore taps. Call it on the main thread.
 */
@androidx.annotation.OptIn(markerClass = [ExperimentalCamera2Interop::class])
internal class CameraFocusController(context: Context, private val scope: CoroutineScope) {
    /** The point the preview marks; null while continuous autofocus runs. */
    var spot by mutableStateOf<FocusSpot?>(null)
        private set

    /** A tapped point could not be brought into focus. */
    var hintVisible by mutableStateOf(false)
        private set

    var canTapToFocus by mutableStateOf(false)
        private set

    private val mainExecutor = ContextCompat.getMainExecutor(context)
    private val sensors = context.getSystemService(SensorManager::class.java)
    private val accelerometer = runCatching { sensors?.getDefaultSensor(Sensor.TYPE_ACCELEROMETER) }.getOrNull()
    private val reframe = ReframeDetector()
    private val spots = FocusSpotState()
    private val afState = MutableStateFlow<Int?>(null)

    /** The callback of the preview built last, and of the one attached (read on camera threads). */
    private var instrumented: CameraCaptureSession.CaptureCallback? = null
    @Volatile private var attachedCallback: CameraCaptureSession.CaptureCallback? = null

    private var camera: Camera? = null
    private var preview: Preview? = null
    private var previewView: PreviewView? = null
    private var capabilities = FocusCapabilities.NONE

    /** CameraX holds a chosen point (auto-cancel off) until [releaseLock]. */
    private var locked = false
    private var macroOverride = false
    private var capturing = false
    private var scanJob: Job? = null
    private var holdJob: Job? = null
    private var hintJob: Job? = null
    private var clearJob: Job? = null
    private var watchingMotion = false
    private var watchedSpot = 0L

    private val motionListener = object : SensorEventListener {
        override fun onSensorChanged(event: SensorEvent) {
            val values = event.values
            if (values.size < 3 || !reframe.onSample(values[0], values[1], values[2], SystemClock.elapsedRealtime())) return
            val id = watchedSpot
            stopWatchingMotion()
            if (!capturing && spots.isCurrent(id)) resumeContinuous()
        }

        override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit
    }

    /** Lets the controller follow the preview's autofocus state. Call before building it. */
    fun instrument(builder: Preview.Builder) {
        val callback = object : CameraCaptureSession.CaptureCallback() {
            override fun onCaptureCompleted(
                session: CameraCaptureSession,
                request: CaptureRequest,
                result: TotalCaptureResult,
            ) {
                // A preview from an earlier binding can still deliver a frame or two.
                if (attachedCallback === this) afState.value = result.get(CaptureResult.CONTROL_AF_STATE)
            }
        }
        instrumented = callback
        Camera2Interop.Extender(builder).setSessionCaptureCallback(callback)
    }

    /** The screen bound [camera] with [preview] (built after [instrument]) showing in [previewView]. */
    fun attach(camera: Camera, preview: Preview, previewView: PreviewView) {
        detach()
        this.camera = camera
        this.preview = preview
        this.previewView = previewView
        attachedCallback = instrumented
        capabilities = focusCapabilities(camera.cameraInfo)
        canTapToFocus = capabilities.tapToFocus
        // CameraX keeps Camera2 overrides per camera, so a macro override an earlier screen
        // could not clear would otherwise pin this one to close-up focus.
        clearMacroOverride(camera)
    }

    /**
     * Back to continuous autofocus and forget the camera, e.g. when it is unbound. With
     * [only], nothing happens unless that camera is the attached one.
     */
    fun detach(only: Camera? = null) {
        if (only != null && only !== camera) return
        scanJob?.cancel()
        holdJob?.cancel()
        clearJob?.cancel()
        hideHint()
        stopWatchingMotion()
        camera?.let(::releaseLock)
        attachedCallback = null
        camera = null
        preview = null
        previewView = null
        capabilities = FocusCapabilities.NONE
        canTapToFocus = false
        capturing = false
        afState.value = null
        spots.clear()
        publish()
    }

    /** Where the camera image sits in the preview, in its pixels. */
    fun contentRect(): PreviewRect {
        val view = previewView ?: return PreviewRect(0f, 0f, 0f, 0f)
        val ratio = if (view.scaleType == PreviewView.ScaleType.FIT_CENTER) {
            preview?.resolutionInfo?.let { shownAspectRatio(it.cropRect.width(), it.cropRect.height(), it.rotationDegrees) }
        } else null
        return previewContentRect(view.width.toFloat(), view.height.toFloat(), ratio)
    }

    /** The user tapped the preview at ([x], [y]) in its pixels. */
    fun onTap(x: Float, y: Float) {
        val camera = camera ?: return
        if (capturing || !capabilities.tapToFocus || !contentRect().contains(x, y)) return
        startScan(camera, x, y, FocusSource.TAP)
    }

    /** Accessibility action: focus on the middle of the image. */
    fun focusCenter() {
        val rect = contentRect()
        onTap(rect.centerX, rect.centerY)
    }

    /**
     * Gets focus right before a photo; returns true when it waited or refocused, so frames
     * from before the call may be soft. Pair with [captureFinished].
     */
    suspend fun prepareForCapture(): Boolean {
        val camera = camera ?: return false
        capturing = true
        stopWatchingMotion()
        hideHint()
        var waited = false
        // A tap just before the shutter: use that scan rather than starting another.
        scanJob?.takeIf { it.isActive }?.let { job ->
            waited = true
            withTimeoutOrNull(TAP_SCAN_WAIT_MS) { job.join() }
        }
        if (this.camera !== camera || spots.spot?.phase == FocusPhase.FOCUSING) return waited
        var plan = preCapturePlan(capabilities, spots.spot, afState.value)
        if (plan == PreCapture.WAIT_FOR_SCAN) {
            waited = true
            withTimeoutOrNull(SETTLE_TIMEOUT_MS) { afState.first { it == null || !isScanningAfState(it) } }
            plan = afterSettling(afState.value)
        }
        if (plan != PreCapture.FOCUS_FIRST || this.camera !== camera) return waited
        val rect = contentRect()
        startScan(camera, rect.centerX, rect.centerY, FocusSource.CAPTURE).join()
        return true
    }

    /** The photo is done (saved or failed): a tapped point keeps holding, anything else resumes. */
    fun captureFinished() {
        capturing = false
        if (camera == null) return
        val current = spots.spot ?: return
        when {
            current.source == FocusSource.CAPTURE -> resumeContinuous()
            current.phase == FocusPhase.FOCUSED || current.phase == FocusPhase.METERED -> holdTapLock(current.id)
            // A failed tap already resumed continuous autofocus; a running one finishes on its own.
            else -> Unit
        }
    }

    private fun startScan(camera: Camera, x: Float, y: Float, source: FocusSource): Job {
        scanJob?.cancel()
        holdJob?.cancel()
        clearJob?.cancel()
        hideHint()
        stopWatchingMotion()
        val started = spots.start(x, y, source, autofocus = capabilities.focusAtPoint)
        publish()
        val timeout = if (source == FocusSource.TAP) TAP_SCAN_TIMEOUT_MS else CAPTURE_SCAN_TIMEOUT_MS
        return scope.launch {
            val result = withTimeoutOrNull(timeout) { scan(camera, started.id, x, y) }
            onScanFinished(camera, started, result)
        }.also { scanJob = it }
    }

    /** True when focused (or exposed, without autofocus), false when it could not focus, null when refused. */
    private suspend fun scan(camera: Camera, id: Long, x: Float, y: Float): Boolean? {
        val factory = previewView?.meteringPointFactory ?: return null
        val caps = capabilities
        val builder = if (caps.focusAtPoint) {
            FocusMeteringAction.Builder(factory.createPoint(x, y, AF_POINT_SIZE), FocusMeteringAction.FLAG_AF).apply {
                if (caps.meterAtPoint) addPoint(factory.createPoint(x, y, AE_POINT_SIZE), FocusMeteringAction.FLAG_AE)
            }
        } else {
            FocusMeteringAction.Builder(factory.createPoint(x, y, AE_POINT_SIZE), FocusMeteringAction.FLAG_AE)
        }
        // Released here (motion, timeout, photo), not by CameraX, so a macro override ends with it.
        val action = builder.disableAutoCancel().build()
        // A new point starts in the normal range.
        if (macroOverride) clearMacroOverride(camera)
        locked = true
        val first = camera.cameraControl.startFocusAndMetering(action).awaitResult().getOrNull() ?: return null
        if (!caps.focusAtPoint || first.isFocusSuccessful) return true
        // Too close for the normal range: some lenses still focus in the close-up range.
        if (!caps.macro || !spots.retryingInMacro(id)) return false
        publish()
        val interop = runCatching { Camera2CameraControl.from(camera.cameraControl) }.getOrNull() ?: return false
        macroOverride = true
        interop.setCaptureRequestOptions(
            CaptureRequestOptions.Builder()
                .setCaptureRequestOption(CaptureRequest.CONTROL_AF_MODE, CameraMetadata.CONTROL_AF_MODE_MACRO)
                .build()
        ).awaitResult()
        return camera.cameraControl.startFocusAndMetering(action).awaitResult().getOrNull()?.isFocusSuccessful == true
    }

    private fun onScanFinished(camera: Camera, finished: FocusSpot, result: Boolean?) {
        if (this.camera !== camera || !spots.isCurrent(finished.id)) return
        when {
            result == null -> {
                spots.clear(finished.id)
                publish()
                releaseLock(camera)
            }
            // The photo is taken at whatever this found; captureFinished resumes afterwards.
            finished.source == FocusSource.CAPTURE -> {
                spots.finish(finished.id, result)
                publish()
            }
            result -> {
                spots.finish(finished.id, focused = true)
                publish()
                holdTapLock(finished.id)
            }
            else -> {
                spots.finish(finished.id, focused = false)
                publish()
                // A failed lock is no better than continuous autofocus.
                releaseLock(camera)
                showHint()
                clearJob = scope.launch {
                    delay(FAILED_SPOT_MS)
                    if (spots.clear(finished.id)) publish()
                }
            }
        }
    }

    private fun holdTapLock(id: Long) {
        holdJob?.cancel()
        val watches = startWatchingMotion(id)
        holdJob = scope.launch {
            delay(tapHoldMillis(watches))
            if (!capturing && spots.isCurrent(id)) resumeContinuous()
        }
    }

    private fun resumeContinuous() {
        holdJob?.cancel()
        clearJob?.cancel()
        stopWatchingMotion()
        spots.clear()
        publish()
        camera?.let(::releaseLock)
    }

    private fun releaseLock(camera: Camera) {
        if (locked) {
            locked = false
            camera.cameraControl.cancelFocusAndMetering()
        }
        if (macroOverride) clearMacroOverride(camera)
    }

    private fun clearMacroOverride(camera: Camera) {
        macroOverride = false
        val interop = runCatching { Camera2CameraControl.from(camera.cameraControl) }.getOrNull() ?: return
        // The app sets no other Camera2 options, so clearing all of them only drops the AF mode.
        val pinned = runCatching { interop.captureRequestOptions.getCaptureRequestOption(CaptureRequest.CONTROL_AF_MODE) }.getOrNull()
        if (pinned != null) interop.clearCaptureRequestOptions()
    }

    private fun startWatchingMotion(id: Long): Boolean {
        stopWatchingMotion()
        val sensor = accelerometer ?: return false
        watchedSpot = id
        reframe.reset(SystemClock.elapsedRealtime())
        watchingMotion = runCatching {
            sensors?.registerListener(motionListener, sensor, SensorManager.SENSOR_DELAY_UI) == true
        }.getOrDefault(false)
        return watchingMotion
    }

    private fun stopWatchingMotion() {
        if (!watchingMotion) return
        watchingMotion = false
        runCatching { sensors?.unregisterListener(motionListener) }
    }

    private fun showHint() {
        hintJob?.cancel()
        hintVisible = true
        hintJob = scope.launch {
            delay(HINT_MS)
            hintVisible = false
        }
    }

    private fun hideHint() {
        hintJob?.cancel()
        hintVisible = false
    }

    private fun publish() {
        spot = spots.spot
    }

    private suspend fun <T> ListenableFuture<T>.awaitResult(): Result<T> = suspendCancellableCoroutine { continuation ->
        addListener({
            val result = runCatching { get() }
            if (continuation.isActive) continuation.resume(result)
        }, mainExecutor)
    }

    private companion object {
        /** CameraX's CameraController sizes: a sixth of the view to focus, a quarter to expose. */
        const val AF_POINT_SIZE = 1f / 6f
        const val AE_POINT_SIZE = 0.25f

        /** A normal scan and a close-up retry; CameraX gives up on each after 5 s. */
        const val TAP_SCAN_TIMEOUT_MS = 6_000L

        /** The shutter waits at most this long for focus before taking the photo anyway. */
        const val CAPTURE_SCAN_TIMEOUT_MS = 2_500L
        const val TAP_SCAN_WAIT_MS = 2_500L
        const val SETTLE_TIMEOUT_MS = 1_000L
        const val HINT_MS = 3_000L
        const val FAILED_SPOT_MS = 1_200L
    }
}

/** A focus controller tied to this composition; it lets go of the camera when it leaves. */
@Composable
internal fun rememberCameraFocusController(): CameraFocusController {
    val context = LocalContext.current.applicationContext
    val scope = rememberCoroutineScope()
    val controller = remember(context, scope) { CameraFocusController(context, scope) }
    DisposableEffect(controller) { onDispose { controller.detach() } }
    return controller
}

/**
 * Tap-to-focus layer for a camera preview: place it over the PreviewView, below the
 * camera's buttons. It marks the tapped point, turning the accent colour once focused, and
 * shows a short hint when the camera cannot focus there.
 */
@Composable
internal fun CameraFocusOverlay(
    focus: CameraFocusController,
    enabled: Boolean,
    modifier: Modifier = Modifier,
    hintTopPadding: Dp = 80.dp,
) {
    val previewLabel = stringResource(R.string.cd_camera_preview)
    val focusLabel = stringResource(R.string.camera_focus_action)
    val tappable = enabled && focus.canTapToFocus
    Box(
        modifier
            .fillMaxSize()
            .pointerInput(tappable) {
                if (tappable) detectTapGestures(onTap = { offset -> focus.onTap(offset.x, offset.y) })
            }
            .semantics {
                contentDescription = previewLabel
                if (tappable) {
                    onClick(label = focusLabel) {
                        focus.focusCenter()
                        true
                    }
                }
            }
    ) {
        focus.spot?.let { FocusRing(it, focus.contentRect()) }
        AnimatedVisibility(
            visible = focus.hintVisible,
            enter = fadeIn(),
            exit = fadeOut(),
            modifier = Modifier
                .align(Alignment.TopCenter)
                .padding(top = hintTopPadding, start = 24.dp, end = 24.dp)
        ) {
            Text(
                stringResource(R.string.camera_focus_failed_hint),
                color = Color.White,
                fontSize = 14.sp,
                fontWeight = FontWeight.SemiBold,
                textAlign = TextAlign.Center,
                modifier = Modifier
                    .semantics { liveRegion = LiveRegionMode.Polite }
                    .background(Color.Black.copy(alpha = 0.6f), RoundedCornerShape(18.dp))
                    .padding(horizontal = 14.dp, vertical = 8.dp)
            )
        }
    }
}

private val FocusRingSize = 72.dp

@Composable
private fun FocusRing(spot: FocusSpot, bounds: PreviewRect) {
    val radius = with(LocalDensity.current) { FocusRingSize.toPx() / 2f }
    val (centerX, centerY) = ringCenter(spot.x, spot.y, bounds, radius)
    val scale = remember(spot.id) { Animatable(1.3f) }
    val alpha = remember(spot.id) { Animatable(1f) }
    LaunchedEffect(spot.id) { scale.animateTo(1f, tween(durationMillis = 200)) }
    LaunchedEffect(spot.id, spot.phase) {
        if (spot.phase == FocusPhase.FOCUSING) return@LaunchedEffect
        // The lock outlives the mark: it fades once the result has been seen.
        delay(if (spot.phase == FocusPhase.FOCUSED) 900L else 600L)
        alpha.animateTo(0f, tween(durationMillis = 400))
    }
    val color by animateColorAsState(
        if (spot.phase == FocusPhase.FOCUSED) AppColors.Calorie else Color.White,
        label = "focusRingColor"
    )
    val dimmed = if (spot.phase == FocusPhase.NOT_FOCUSED) 0.6f else 1f
    Box(
        Modifier
            .offset { IntOffset((centerX - radius).roundToInt(), (centerY - radius).roundToInt()) }
            .size(FocusRingSize)
            .graphicsLayer {
                scaleX = scale.value
                scaleY = scale.value
                this.alpha = alpha.value * dimmed
            }
            .border(2.dp, color, CircleShape),
        contentAlignment = Alignment.Center
    ) {
        // The usual close-up symbol while the camera focuses in its macro range.
        if (spot.macro) Icon(Icons.Filled.LocalFlorist, contentDescription = null, tint = color, modifier = Modifier.size(18.dp))
    }
}
