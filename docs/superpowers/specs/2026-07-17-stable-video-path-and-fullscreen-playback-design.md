# SwingArc Stable Video Path and Fullscreen Playback Design

**Date:** 2026-07-17  
**Status:** Confirmed direction, pending implementation

## Objective

Fix saved projects showing a black video after an App update, and add true full-screen video playback on iPhone and iPad without losing playback position or visible analysis overlays.

## Confirmed root cause

Imported and recorded videos are copied into `Library/Application Support/SwingArcVideos`, but project metadata currently persists each video's complete sandbox URL. The application data container UUID can change when a new build is installed. The files move with the application data, while the stored absolute URL still contains the old container UUID.

The project then opens an `AVAsset` at a path that no longer exists. The player has no valid media, so the canvas appears black even though the video remains in the current `SwingArcVideos` directory.

## Stable media identity

### New persistence rule

- Media managed by SwingArc is identified by its stable file name inside `SwingArcVideos`.
- Runtime URLs are always reconstructed from the current Application Support directory.
- Project identity, analysis state, P1-P8 markers, and drawings must no longer depend on a sandbox container UUID.
- Existing project IDs, names, modification dates, status, duration, and source frame rate are preserved during migration.

### Legacy migration

When the project index is loaded:

1. If the persisted URL exists, use it and normalize managed media to the stable representation.
2. If it does not exist, take its last path component and look for that file in the current `SwingArcVideos` directory.
3. If found, rebuild the runtime URL, migrate the associated analysis payload from the old project key to the stable key, update `lastVideoURL`, and rewrite the project index.
4. Migration must be idempotent: reopening the App must not duplicate or repeatedly modify projects.
5. If no matching file exists, retain the project metadata but mark the media unavailable instead of attempting playback.

The resolver must not silently attach a project to an unrelated external file. Filename recovery is limited to SwingArc-managed media under `SwingArcVideos`.

### Missing-media presentation

- Validate file availability before creating or loading the player.
- Replace the black canvas/infinite loading state with an explicit message: `视频文件缺失`.
- Provide a back action so the user can return to the project library.
- Do not delete P1-P8 markers or manual drawings when media is missing.

## Full-screen playback

### Entry and presentation

- Add a standard expand icon at the upper-right of the video canvas.
- Do not show the entry control while drawing, so it cannot conflict with annotation gestures.
- Present a true full-screen surface that ignores safe-area chrome and reuses the existing `VideoPlaybackManager` and `AVPlayer`.
- Entering or leaving full screen must preserve current time, play/pause state, playback rate, and the loaded asset.

### Visible content

The confirmed mode is **video plus compact controls**:

- Keep saved drawings and enabled pose/head/spine/grid overlays visible.
- Disable drawing creation and editing in full screen.
- Hide the workspace header, P1-P8 strip, drawing toolbar, analysis progress, results UI, and project sidebars.
- Keep aspect-fit video presentation by default, with black background where required.

### Controls and gestures

- A single tap reveals or hides compact playback controls.
- Visible controls include close full screen, previous frame, play/pause, and next frame.
- Controls auto-hide after a short delay while playback continues.
- Pinch zoom remains available in idle full-screen playback.
- Double tap resets zoom to 1x, matching the existing canvas behavior.
- Touch targets remain at least 44 points on iPhone and iPad.

### Device behavior

- Use the same presentation and state model on iPhone and iPad.
- Layout must adapt to portrait and landscape bounds without introducing a second player or reloading the asset.
- Dismissing full screen returns to the exact workspace and frame that were visible before entry.

## State ownership

- `ContentView` continues to own project selection and persistence.
- `AnalysisWorkspaceView` owns whether full screen is presented.
- `VideoPlaybackManager` remains the single owner of the player and playback state.
- A reusable video surface renders the player and overlays in normal or full-screen mode, with drawing interaction explicitly disabled for full screen.
- Full-screen control visibility and auto-hide timing are view-only state and must not be written to project persistence.

## Verification

Automated coverage must verify:

- a legacy absolute sandbox URL resolves to the current managed-media directory;
- the legacy analysis payload migrates to the stable key;
- migration is idempotent and preserves project metadata;
- a genuinely missing file is reported as unavailable and its annotations remain stored;
- newly saved projects survive a simulated container-root change;
- full-screen presentation reuses the same playback manager/player;
- entry/exit preserves time, playback rate, and play/pause state;
- full-screen drawing interaction is disabled while overlays remain enabled.

Manual device verification must cover:

1. Import a video, analyze or draw on it, close and reopen it.
2. Install an updated build without deleting App data.
3. Open the saved project and confirm video, drawings, and P1-P8 markers are restored.
4. Enter full screen, play, pause, step frames, zoom, and exit.
5. Confirm the workspace returns at the same frame and state.
6. Repeat the full-screen check on iPhone and an iPad simulator layout.

## Out of scope

- Drawing or editing annotations while full screen.
- Showing the P1-P8 timeline or analysis controls in full screen.
- Replacing the custom player with `AVPlayerViewController`.
- Recovering videos that were actually deleted from the App container.
