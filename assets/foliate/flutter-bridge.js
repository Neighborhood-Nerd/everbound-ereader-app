// Import view.js to register the foliate-view custom element
// This MUST be imported before we try to use foliate-view
import './view.js';
import { Overlayer } from './overlayer.js';
import { fromRange, joinIndir } from './epubcfi.js';
import {
    normalizeProgressXPointer,
    findTextNodeAtOffset,
    adjustSpineIndex,
    extractSpineIndexFromXPath,
    convertXPathToCFI,
    convertCFIToXPointer
} from './xcfi.js';

/**
 * Flutter Bridge Module
 * 
 * This module exposes a clean API for Flutter to call JavaScript functions.
 * It handles all communication between the InAppWebView and Flutter.
 */

const logToFlutter = (msg) => {
    try {
        console.log('[foliate-bridge]', msg);
        window.flutter_inappwebview?.callHandler('jsLog', msg);
    } catch (e) {
        console.error('Error sending jsLog to Flutter', e);
    }
};

// Error tracking
window.addEventListener('error', (e) => {
    logToFlutter(`JS error: ${e.message} at ${e.filename}:${e.lineno}`);
});

window.addEventListener('unhandledrejection', (e) => {
    logToFlutter(`Unhandled promise rejection: ${e.reason}`);
});

// ============================================================================
// STATE MANAGEMENT
// ============================================================================

let foliateView = null;
const container = document.getElementById('foliate-container');
const pendingAnnotations = new Map();
const overlayCreatedIndices = new Set(); // Track which sections have had create-overlay fire
let currentTheme = null;
let attachSelectionListenersGlobal = null;
let currentSectionInfo = null; // Track current section index and base CFI for CFI calculation
let animationDuration = 300; // Default animation duration in milliseconds

// Initialize the global animation duration variable that paginator.js uses
// This must be set before paginator.js loads
window.foliateAnimationDuration = window.foliateAnimationDuration || 300;

// ============================================================================
// FOLIATE VIEW INITIALIZATION
// ============================================================================

const ensureView = async () => {
    if (foliateView) return foliateView;

    // Wait for foliate-view custom element to be registered (comes from reader.js import of view.js)
    // Check every 100ms for up to 5 seconds
    let attempts = 0;
    while (!customElements.get('foliate-view') && attempts < 50) {
        await new Promise(r => setTimeout(r, 100));
        attempts++;
    }

    if (!customElements.get('foliate-view')) {
        logToFlutter('ERROR: foliate-view element not registered after 5 seconds');
        throw new Error('foliate-view custom element not available');
    }

    const view = document.createElement('foliate-view');
    view.id = 'foliate-view';
    container.appendChild(view);

    logToFlutter('foliate-view element created successfully');

    // Relay events to Flutter
    view.addEventListener('relocate', async (event) => {
        const detail = event.detail || {};

        // If we have CFI but no XPath, convert CFI to XPointer
        // This ensures we always have XPath for KOReader sync
        if (detail.cfi && !detail.xpointer && !detail.startXpath) {
            try {
                const xpointerResult = await convertCFIToXPointer(view, detail.cfi);
                if (xpointerResult && xpointerResult.xpointer) {
                    // Normalize the XPointer (remove trailing /text().N and .N suffixes)
                    const normalizedXPointer = normalizeProgressXPointer(xpointerResult.xpointer);
                    detail.xpointer = normalizedXPointer;
                    detail.startXpath = normalizedXPointer;
                    detail.endXpath = normalizeProgressXPointer(xpointerResult.pos1 || xpointerResult.xpointer);
                    logToFlutter(`Converted CFI to XPointer: ${normalizedXPointer.substring(0, Math.min(50, normalizedXPointer.length))}...`);
                }
            } catch (error) {
                logToFlutter(`Failed to convert CFI to XPointer: ${error.message}`);
                // Continue without XPointer - we'll skip sync for this update
            }
        }

        window.flutter_inappwebview?.callHandler('relocated', detail);
    });

    // Add touch event listeners to send touch coordinates to Flutter
    // This allows Flutter to implement custom touch zones (e.g., top/bottom nav areas)
    // Only fires for simple taps that don't interfere with page swiping or selection
    let touchStartTime = 0;
    let touchStartPosition = null;
    let touchMoved = false;

    const handleTouchStart = (e) => {
        // Only track single touches
        if (e.touches.length === 1) {
            const touch = e.touches[0];

            // Get coordinates relative to window (not iframe)
            let windowX = touch.clientX;
            let windowY = touch.clientY;

            // Check if touch is from an iframe and convert to window coordinates
            const targetDoc = e.target?.ownerDocument;
            if (targetDoc && targetDoc.defaultView && targetDoc.defaultView !== window) {
                // Touch is from an iframe - need to get iframe's position
                const iframe = targetDoc.defaultView.frameElement;
                if (iframe) {
                    const iframeRect = iframe.getBoundingClientRect();
                    // Convert iframe-relative coordinates to window coordinates
                    windowX = iframeRect.left + touch.clientX;
                    windowY = iframeRect.top + touch.clientY;
                }
            }

            touchStartTime = Date.now();
            touchStartPosition = {
                x: windowX,
                y: windowY,
                screenX: touch.screenX,
                screenY: touch.screenY,
            };
            touchMoved = false;
            logToFlutter(`Touch start: window-relative=(${windowX}, ${windowY})`);
        }
    };

    const handleTouchMove = (e) => {
        // Mark as moved if there's significant movement (more than 10px)
        // This prevents tap events from firing during swipes
        if (touchStartPosition && e.touches.length === 1) {
            const touch = e.touches[0];

            // Get coordinates relative to window (not iframe)
            let windowX = touch.clientX;
            let windowY = touch.clientY;

            // Check if touch is from an iframe and convert to window coordinates
            const targetDoc = e.target?.ownerDocument;
            if (targetDoc && targetDoc.defaultView && targetDoc.defaultView !== window) {
                // Touch is from an iframe - need to get iframe's position
                const iframe = targetDoc.defaultView.frameElement;
                if (iframe) {
                    const iframeRect = iframe.getBoundingClientRect();
                    // Convert iframe-relative coordinates to window coordinates
                    windowX = iframeRect.left + touch.clientX;
                    windowY = iframeRect.top + touch.clientY;
                }
            }

            const deltaX = Math.abs(windowX - touchStartPosition.x);
            const deltaY = Math.abs(windowY - touchStartPosition.y);
            if (deltaX > 10 || deltaY > 10) {
                touchMoved = true;
            }
        }
    };

    const handleTouchEnd = async (e) => {
        if (e.changedTouches.length > 0 && touchStartPosition) {
            const touch = e.changedTouches[0];
            const touchDuration = Date.now() - touchStartTime;

            logToFlutter(`Touch end: moved=${touchMoved}, duration=${touchDuration}ms`);

            if (!touchMoved) {
                // Check if there's an active selection - if so, don't fire tap event
                // This prevents interference with text selection
                const doc = view.shadowRoot?.querySelector('iframe')?.contentDocument || document;
                const selection = doc?.getSelection();
                if (selection && selection.rangeCount > 0 && !selection.isCollapsed) {
                    logToFlutter('Touch end: active selection detected, skipping tap');
                    touchStartPosition = null;
                    return;
                }

                // Only fire for simple taps (short duration, no movement)
                // This ensures we don't interfere with page swiping
                if (touchDuration < 300) { // Max 300ms for a tap
                    // Get coordinates relative to window (not iframe)
                    // touch.clientX/clientY are relative to the viewport where the event occurred
                    // If the event is from an iframe, we need to convert to window coordinates
                    let windowX = touch.clientX;
                    let windowY = touch.clientY;

                    // Check if touch is from an iframe and convert to window coordinates
                    const targetDoc = e.target?.ownerDocument;
                    if (targetDoc && targetDoc.defaultView && targetDoc.defaultView !== window) {
                        // Touch is from an iframe - need to get iframe's position
                        const iframe = targetDoc.defaultView.frameElement;
                        if (iframe) {
                            const iframeRect = iframe.getBoundingClientRect();
                            // Convert iframe-relative coordinates to window coordinates
                            windowX = iframeRect.left + touch.clientX;
                            windowY = iframeRect.top + touch.clientY;
                            logToFlutter(`Touch from iframe: iframe pos=(${iframeRect.left}, ${iframeRect.top}), iframe-relative=(${touch.clientX}, ${touch.clientY}), window-relative=(${windowX}, ${windowY})`);
                        }
                    }

                    const touchEndPosition = {
                        x: windowX,
                        y: windowY,
                        screenX: touch.screenX,
                        screenY: touch.screenY,
                    };

                    // Calculate delta (should be small for taps)
                    // Both touchStartPosition and touchEndPosition are now window-relative
                    const deltaX = touchEndPosition.x - touchStartPosition.x;
                    const deltaY = touchEndPosition.y - touchStartPosition.y;

                    logToFlutter(`Touch end: delta=(${deltaX}, ${deltaY}), duration=${touchDuration}ms`);

                    // Only send if movement is minimal (tap, not swipe)
                    if (Math.abs(deltaX) < 10 && Math.abs(deltaY) < 10) {
                        let isAnnotationTap = false;
                        try {
                            // Get the document where the touch occurred
                            const touchDoc = targetDoc || (view.shadowRoot?.querySelector('iframe')?.contentDocument || document);

                            // Find the section index for this document
                            const renderer = view.renderer;
                            if (renderer && renderer.getContents) {
                                const contents = renderer.getContents();
                                const contentInfo = contents.find(c => c.doc === touchDoc);

                                if (contentInfo && contentInfo.overlayer) {
                                    // Convert window coordinates to iframe-relative coordinates for hitTest
                                    // hitTest expects coordinates relative to the document where the overlayer is
                                    let hitTestX = touch.clientX;
                                    let hitTestY = touch.clientY;

                                    // If touch is from an iframe, coordinates are already iframe-relative
                                    // If touch is from main document, we need to check if there's an iframe offset
                                    if (targetDoc && targetDoc.defaultView && targetDoc.defaultView !== window) {
                                        // Touch is from iframe, coordinates are already iframe-relative
                                        hitTestX = touch.clientX;
                                        hitTestY = touch.clientY;
                                    } else {
                                        // Touch is from main document - check if we need to convert
                                        // For main document touches, coordinates are already document-relative
                                        hitTestX = touch.clientX;
                                        hitTestY = touch.clientY;
                                    }

                                    // Perform hit test
                                    const hitResult = contentInfo.overlayer.hitTest({ x: hitTestX, y: hitTestY });
                                    if (hitResult && hitResult.length > 0 && hitResult[0]) {
                                        const annotationValue = hitResult[0];
                                        // Skip if it's a search result (starts with SEARCH_PREFIX)
                                        if (!annotationValue.startsWith('search:')) {
                                            isAnnotationTap = true;
                                            logToFlutter(`Touch end: annotation tapped (${annotationValue.substring(0, 30)}...), calling view.showAnnotation`);

                                            // Use foliate-js's showAnnotation method which will:
                                            // 1. Navigate to the annotation location if needed
                                            // 2. Get the proper range from the anchor
                                            // 3. Emit the 'show-annotation' event with all details
                                            // The existing 'show-annotation' event listener will then call Flutter with correct rect info
                                            (async () => {
                                                try {
                                                    const view = await ensureView();
                                                    if (view) {
                                                        await view.showAnnotation({ value: annotationValue });
                                                        logToFlutter(`Successfully called view.showAnnotation for ${annotationValue.substring(0, 30)}...`);
                                                    } else {
                                                        logToFlutter(`Error: view not available for showAnnotation`);
                                                        // Fallback: call Flutter handler directly with just the value
                                                        window.flutter_inappwebview?.callHandler('showAnnotation', {
                                                            value: annotationValue
                                                        });
                                                    }
                                                } catch (err) {
                                                    logToFlutter(`Error calling view.showAnnotation: ${err.message}`);
                                                    // Fallback: call Flutter handler directly with just the value
                                                    window.flutter_inappwebview?.callHandler('showAnnotation', {
                                                        value: annotationValue
                                                    });
                                                }
                                            })();
                                        }
                                    }
                                }
                            }
                        } catch (e) {
                            logToFlutter(`Error checking annotation hitTest: ${e.message}`);
                            // Continue with touch event if hitTest fails
                        }

                        // Only send touchEvent if not an annotation tap
                        if (!isAnnotationTap) {
                            // Normalize by window dimensions (now that coordinates are window-relative)
                            const normalizedX = windowX / window.innerWidth;
                            const normalizedY = windowY / window.innerHeight;
                            logToFlutter(`Sending tap event: window-relative=(${windowX}, ${windowY}), normalized=(${normalizedX.toFixed(2)}, ${normalizedY.toFixed(2)})`);

                            // Send tap event to Flutter with normalized coordinates
                            window.flutter_inappwebview?.callHandler('touchEvent', {
                                type: 'tap',
                                x: windowX,
                                y: windowY,
                                normalizedX: normalizedX, // 0.0 to 1.0
                                normalizedY: normalizedY, // 0.0 to 1.0
                                viewportWidth: window.innerWidth,
                                viewportHeight: window.innerHeight,
                            });
                        }
                    } else {
                        logToFlutter(`Touch end: movement too large (${Math.abs(deltaX)}, ${Math.abs(deltaY)}), not a tap`);
                    }
                } else {
                    logToFlutter(`Touch end: duration too long (${touchDuration}ms), not a tap`);
                }
            } else {
                logToFlutter('Touch end: touch moved, not a tap');
            }

            touchStartPosition = null;
            touchMoved = false;
        }
    };

    // Add touch listeners to capture taps for custom touch zones
    // Foliate uses iframes, so we need to attach to both the view and iframe documents
    const attachTouchListeners = (targetDoc) => {
        if (!targetDoc) return;
        try {
            targetDoc.addEventListener('touchstart', handleTouchStart, { passive: true, capture: false });
            targetDoc.addEventListener('touchmove', handleTouchMove, { passive: true, capture: false });
            targetDoc.addEventListener('touchend', handleTouchEnd, { passive: true, capture: false });
            logToFlutter('Touch listeners attached to document');
        } catch (e) {
            logToFlutter(`Error attaching touch listeners: ${e.message}`);
        }
    };

    // Attach to main document
    attachTouchListeners(document);

    // Also attach to view's shadow root if it exists
    if (view.shadowRoot) {
        attachTouchListeners(view.shadowRoot);
    }

    // Attach to iframe documents when sections load (foliate uses iframes for content)
    view.addEventListener('load', (event) => {
        const { detail } = event;
        const { doc, index } = detail || {};

        // Attach touch listeners to the iframe's content document
        if (doc) {
            attachTouchListeners(doc);
            logToFlutter(`Touch listeners attached to section ${index} document`);
        }

        // Track current section info for CFI calculation during selection
        if (foliateView?.book?.sections?.[index]) {
            const baseCFI = foliateView.book.sections[index].cfi;
            currentSectionInfo = { index, baseCFI, doc };
            logToFlutter(`Loaded section ${index}, baseCFI: ${baseCFI?.substring(0, 30)}...`);
        }

        window.flutter_inappwebview?.callHandler('sectionLoaded', detail || {});

        // Apply current theme to newly loaded section
        if (doc && currentTheme) {
            try {
                const { backgroundColor, textColor, fontSize } = currentTheme;

                // Apply via inline styles first
                if (backgroundColor) {
                    doc.body.style.backgroundColor = backgroundColor;
                    doc.documentElement.style.backgroundColor = backgroundColor;
                }
                if (textColor) {
                    doc.body.style.color = textColor;
                    doc.documentElement.style.color = textColor;
                }
                if (fontSize) {
                    doc.body.style.fontSize = `${fontSize}px`;
                    doc.documentElement.style.fontSize = `${fontSize}px`;
                }

                // Also apply via a style element for better specificity
                const themeStyleId = 'epub-flutter-theme-style';
                let themeStyle = doc.getElementById(themeStyleId);
                if (!themeStyle) {
                    themeStyle = doc.createElement('style');
                    themeStyle.id = themeStyleId;
                    doc.head.appendChild(themeStyle);
                }
                themeStyle.textContent = generateThemeCSS(currentTheme);

                logToFlutter(`Theme applied to section ${index}`);
            } catch (e) {
                logToFlutter(`Error applying theme to section ${index}: ${e.message}`);
            }
        }

        // Attach selection listeners to newly loaded section so text selection fires callbacks
        if (doc) {
            attachSelectionListeners(doc, index);
            logToFlutter(`Selection listeners attached for section ${index}`);
        }

        // Handle pending annotations when section loads
        if (pendingAnnotations.has(index)) {
            const annotations = pendingAnnotations.get(index);
            logToFlutter(`Section ${index} loaded with ${annotations.length} pending annotations, re-adding in 100ms`);

            setTimeout(() => {
                annotations.forEach((ann) => {
                    view.addAnnotation(ann).catch((e) => {
                        // Silently ignore Range errors that happen when doc isn't quite ready
                        if (!e.message?.includes('Range.setStart')) {
                            logToFlutter(`Error re-adding annotation: ${e.message}`);
                        }
                    });
                });
            }, 100);
        }
    });

    // Handle annotation drawing
    view.addEventListener('draw-annotation', (event) => {
        logToFlutter(`✅ draw-annotation event FIRED!`);
        const { draw, annotation, doc, range } = event.detail || {};

        if (!draw || !annotation || !doc || !range) {
            logToFlutter(`draw-annotation: missing required fields`);
            return;
        }

        // Skip if range isn't ready
        if (typeof range === 'function' || !range.startContainer) {
            logToFlutter(`draw-annotation: range not ready, skipping`);
            return;
        }

        try {
            const style = annotation.style || annotation.type;
            const color = annotation.color;

            if (style === 'highlight') {
                draw(Overlayer.highlight, { color });
                logToFlutter(`✅ Drew highlight with color: ${color}`);
            } else if (['underline', 'squiggly'].includes(style)) {
                const { defaultView } = doc;
                const node = range.startContainer;
                const el = node.nodeType === 1 ? node : node.parentElement;
                const { writingMode } = defaultView.getComputedStyle(el);
                draw(Overlayer[style], { writingMode, color, padding: 2 });
                logToFlutter(`✅ Drew ${style} with color: ${color}`);
            }
        } catch (e) {
            logToFlutter(`draw-annotation error: ${e.message}`);
        }
    });

    // Handle create-overlay event - trigger annotation restoration for initial page load
    // This is critical for ensuring annotations appear when navigating to a saved location
    view.addEventListener('create-overlay', (event) => {
        const { index } = event.detail || {};
        logToFlutter(`🎯 create-overlay event FIRED for index=${index}`);

        // Mark this section as having its overlay created
        overlayCreatedIndices.add(index);

        // Add pending annotations for this section
        if (pendingAnnotations.has(index)) {
            const annotations = pendingAnnotations.get(index);
            logToFlutter(`Adding ${annotations.length} pending annotations for index=${index} (create-overlay triggered)`);

            // Add annotations immediately since overlayer is now ready
            // Add with a small delay to ensure the overlayer is fully initialized
            setTimeout(() => {
                annotations.forEach((ann) => {
                    view.addAnnotation(ann).catch((e) => {
                        if (!e.message?.includes('Range.setStart')) {
                            logToFlutter(`Error adding annotation on create-overlay: ${e.message}`);
                        }
                    });
                });

                // Clear pending annotations for this section only after adding
                pendingAnnotations.delete(index);
                logToFlutter(`Cleared pending annotations for index=${index}`);
            }, 5);
        }
    });

    // Handle show-annotation event - fired when user clicks on an annotation
    // This allows us to show annotation details (notes, etc.) to the user
    view.addEventListener('show-annotation', (event) => {
        const { value } = event.detail || {};
        logToFlutter(`📌 show-annotation event FIRED for value=${value?.substring(0, 30)}...`);

        // Get rect - getRectFromRange handles iframe conversion internally
        const pixelRect = getRectFromRange(event.detail.range);
        const doc = event.detail.range.commonAncestorContainer.ownerDocument;
        const viewport = doc.defaultView;
        if (!viewport) {
            logToFlutter('Warning: No viewport available for annotation');
            return;
        }

        let containerRect;
        if (foliateView) {
            // Use foliate-view element as container for coordinate conversion
            containerRect = foliateView.getBoundingClientRect();
        } else {
            // Fallback to window viewport if foliate-view not available
            containerRect = {
                left: 0,
                top: 0,
                width: window.innerWidth,
                height: window.innerHeight
            };
        }

        // Relay the annotation event to Flutter with raw pixel coordinates and container rect
        window.flutter_inappwebview?.callHandler('showAnnotation', {
            value,
            detail: event.detail,
            rect: pixelRect,  // Send raw pixel coordinates (window-relative)
            containerRect: {  // Send container's bounding rect (iframe or body)
                left: containerRect.left,
                top: containerRect.top,
                width: containerRect.width,
                height: containerRect.height
            }
        });
    });

    foliateView = view;
    return view;
};

// ============================================================================
// EVENT LISTENERS FOR SELECTION (TEXT HIGHLIGHTING)
// ============================================================================

const attachSelectionListeners = (doc, index) => {
    if (!doc || doc.__everboundSelectionAttached) return;

    doc.__everboundSelectionAttached = true;
    doc.__everboundSelectionPollInterval = 25;

    const checkSelection = () => {
        const selection = doc.defaultView?.getSelection?.();
        if (!selection || selection.toString().length === 0) return;

        const range = selection.getRangeAt(0);
        const text = selection.toString();

        if (text.length > 0) {
            logToFlutter(`Selection detected: "${text.substring(0, 50)}..."`);

            // Calculate CFI from range if we have section info
            let cfi = '';
            if (currentSectionInfo) {
                try {
                    const rangeCFI = fromRange(range);
                    if (currentSectionInfo.baseCFI) {
                        cfi = joinIndir(currentSectionInfo.baseCFI, rangeCFI);
                    } else {
                        cfi = rangeCFI;
                    }
                    logToFlutter(`Selection CFI: ${cfi.substring(0, 50)}...`);
                } catch (e) {
                    logToFlutter(`Error calculating CFI: ${e.message}`);
                }
            }

            // Get rect - getRectFromRange handles iframe conversion internally
            const pixelRect = getRectFromRange(range);
            const viewport = doc.defaultView;
            if (!viewport) {
                logToFlutter('Warning: No viewport available');
                return;
            }

            // Get the container's bounding rect (use foliate-view element, not iframe)
            // The foliate-view element is the actual container for accurate coordinate conversion
            let containerRect;
            if (foliateView) {
                // Use foliate-view element as container for coordinate conversion
                containerRect = foliateView.getBoundingClientRect();
                logToFlutter(`Selection container: foliate-view size=${containerRect.width.toFixed(1)}x${containerRect.height.toFixed(1)}, pos=(${containerRect.left.toFixed(1)}, ${containerRect.top.toFixed(1)})`);
            } else {
                // Fallback to window viewport if foliate-view not available
                containerRect = {
                    left: 0,
                    top: 0,
                    width: window.innerWidth,
                    height: window.innerHeight
                };
                logToFlutter(`Selection container: window viewport size=${containerRect.width.toFixed(1)}x${containerRect.height.toFixed(1)}`);
            }

            logToFlutter(`Selection rect: pixel=${pixelRect.left.toFixed(1)},${pixelRect.top.toFixed(1)} size=${pixelRect.width.toFixed(1)}x${pixelRect.height.toFixed(1)}, container=(${containerRect.left.toFixed(1)},${containerRect.top.toFixed(1)})`);

            // Send raw pixel coordinates and container position - Flutter will handle coordinate system conversion
            window.flutter_inappwebview?.callHandler('selection', {
                text,
                cfi,
                rect: pixelRect,  // Send raw pixel coordinates (window-relative)
                containerRect: {  // Send container's bounding rect (iframe or body)
                    left: containerRect.left,
                    top: containerRect.top,
                    width: containerRect.width,
                    height: containerRect.height
                },
                chapterIndex: currentSectionInfo?.index
            });
        }
    };

    doc.addEventListener('selectionchange', checkSelection);
};

/**
 * Get iframe element containing the given range or element
 * Traverses up the DOM tree to find the containing iframe
 */
const getIframeElement = (nodeElement) => {
    let node;
    if (nodeElement && typeof nodeElement === 'object' && 'tagName' in nodeElement) {
        node = nodeElement;
    } else if (nodeElement && typeof nodeElement === 'object' && 'collapse' in nodeElement) {
        node = nodeElement.commonAncestorContainer;
    } else {
        node = nodeElement;
    }
    while (node) {
        if (node.nodeType === Node.DOCUMENT_NODE) {
            const doc = node;
            if (doc.defaultView && doc.defaultView.frameElement) {
                return doc.defaultView.frameElement;
            }
        }
        node = node.parentNode;
    }
    return null;
};

/**
 * Convert iframe-relative rect to window coordinates
 * @param {Object} frame - { left, top } from iframe.getBoundingClientRect()
 * @param {DOMRect} rect - Rect from getClientRects()
 * @param {number} sx - X scale factor from transform matrix
 * @param {number} sy - Y scale factor from transform matrix
 */
const frameRect = (frame, rect, sx = 1, sy = 1) => {
    if (!rect) return { left: 0, right: 0, top: 0, bottom: 0 };
    const left = sx * rect.left + frame.left;
    const right = sx * rect.right + frame.left;
    const top = sy * rect.top + frame.top;
    const bottom = sy * rect.bottom + frame.top;
    return { left, right, top, bottom };
};

/**
 * Get bounding rect from range, converting iframe coordinates to window coordinates
 * Handles coordinate transformation for elements within iframes
 */
const getRectFromRange = (range) => {
    const rects = range.getClientRects();
    if (rects.length === 0) return { left: 0, top: 0, width: 0, height: 0 };

    // Get iframe element if range is in an iframe
    const frameElement = getIframeElement(range);

    // Get frame offset and transform scale factors for coordinate conversion
    let frame = { top: 0, left: 0 };
    let sx = 1, sy = 1;

    if (frameElement) {
        frame = frameElement.getBoundingClientRect();
        // Get transform matrix scale factors for coordinate transformation
        const transform = window.getComputedStyle(frameElement).transform;
        const match = transform.match(/matrix\((.+)\)/);
        if (match) {
            const values = match[1].split(/\s*,\s*/).map(x => parseFloat(x));
            sx = values[0] || 1;
            sy = values[3] || 1;
        }
    }

    // Get zoom factor (Safari doesn't zoom client rects, others do)
    const zoom = /^((?!chrome|android).)*AppleWebKit/i.test(navigator.userAgent) && !window.chrome
        ? parseFloat(window.getComputedStyle(document.body).zoom || 1.0)
        : 1.0;

    // Find bounding box across all rects (apply zoom, then frameRect conversion)
    let minLeft = Infinity, minTop = Infinity, maxRight = -Infinity, maxBottom = -Infinity;

    for (const rect of rects) {
        // Apply zoom first (like overlayer.js does)
        const zoomedRect = {
            left: rect.left * zoom,
            top: rect.top * zoom,
            right: rect.right * zoom,
            bottom: rect.bottom * zoom,
        };

        // Convert to window coordinates using frameRect
        const windowRect = frameRect(frame, zoomedRect, sx, sy);

        minLeft = Math.min(minLeft, windowRect.left);
        minTop = Math.min(minTop, windowRect.top);
        maxRight = Math.max(maxRight, windowRect.right);
        maxBottom = Math.max(maxBottom, windowRect.bottom);
    }

    return {
        left: minLeft,
        top: minTop,
        width: maxRight - minLeft,
        height: maxBottom - minTop
    };
};

// ============================================================================
// PUBLIC API - EXPOSED TO FLUTTER VIA HANDLERS
// ============================================================================

/**
 * Initialize the reader and set up foliate-view
 */
const initReader = async () => {
    await ensureView();
    logToFlutter('Reader initialized');
};


/**
 * Open a book from blob data
 */
const openBook = async (options) => {
    console.log('[foliate-bridge] openBook called with options:', options);
    try {
        logToFlutter('openBook called');
        const view = await ensureView();
        logToFlutter('View ensured');
        const { bytesBase64, initialLocation, progress, theme } = options || {};
        logToFlutter(`openBook options: bytesBase64=${bytesBase64 ? 'present' : 'missing'}, initialLocation=${initialLocation ? JSON.stringify(initialLocation) : 'null'}`);

        if (!bytesBase64) {
            logToFlutter('openBook: no bytesBase64 provided');
            return;
        }

        try {
            const binaryString = atob(bytesBase64);
            const bytes = new Uint8Array(binaryString.length);
            for (let i = 0; i < binaryString.length; i++) {
                bytes[i] = binaryString.charCodeAt(i);
            }
            const blob = new Blob([bytes], { type: 'application/epub+zip' });

            logToFlutter(`Opening book, blob size: ${blob.size}`);
            if (initialLocation) {
                logToFlutter(`openBook: initialLocation=${JSON.stringify(initialLocation)}`);
            }

            // Apply theme BEFORE opening the book to prevent flicker
            if (theme) {
                setTheme(theme);
                logToFlutter(`openBook: theme pre-applied before book load`);
            }

            // Ensure the view element is ready before opening the book
            // On iOS WebView, the element needs to be fully processed by the browser
            // before it can render content properly
            if (!view.isConnected) {
                container.appendChild(view);
            }

            // Wait for the browser to process the DOM update
            // Use multiple requestAnimationFrame calls to ensure the browser has
            // fully processed the element and is ready to render
            const isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent);
            await new Promise(resolve => {
                requestAnimationFrame(() => {
                    requestAnimationFrame(() => {
                        // On iOS, add a longer delay to ensure WebView is fully ready
                        // This helps prevent blank screen on first load
                        if (isIOS) {
                            // Give iOS WebView more time to process the custom element
                            // and set up its shadow DOM properly
                            setTimeout(() => {
                                resolve();
                            }, 150); // Longer delay for iOS WebView
                        } else {
                            resolve();
                        }
                    });
                });
            });

            await view.open(blob);

            // Use view.init() to navigate to saved location if provided
            if (initialLocation) {
                logToFlutter(`Initial location provided: ${JSON.stringify(initialLocation)}`);

                // Extract CFI, XPath, href, or fraction from the location object
                let location = initialLocation.cfi || initialLocation.href || initialLocation.fraction;
                logToFlutter(`Extracted location: ${location ? (typeof location === 'string' ? location.substring(0, 50) : location) : 'null'}`);

                // If location is XPath (starts with /body), convert it to CFI
                if (location && typeof location === 'string' && location.startsWith('/body')) {
                    logToFlutter(`Detected XPath, attempting conversion: ${location.substring(0, Math.min(50, location.length))}`);
                    try {
                        // Wait for book to be available (with longer timeout for initial load)
                        let retries = 0;
                        const maxRetries = 50; // Increased from 20 to 50 (2.5 seconds)
                        while (!view.book && retries < maxRetries) {
                            await new Promise(resolve => setTimeout(resolve, 50));
                            retries++;
                        }

                        if (!view.book) {
                            logToFlutter(`⚠️ Book not available after ${maxRetries} retries, cannot convert XPath`);
                            // Don't try to navigate with XPath - it won't work
                            location = null;
                        } else {
                            logToFlutter(`Book available, converting XPath to CFI`);
                            // Also wait for sections to be loaded
                            let sectionsReady = false;
                            let sectionRetries = 0;
                            while (!sectionsReady && sectionRetries < 20) {
                                if (view.book.sections && view.book.sections.length > 0) {
                                    sectionsReady = true;
                                } else {
                                    await new Promise(resolve => setTimeout(resolve, 50));
                                    sectionRetries++;
                                }
                            }

                            if (!sectionsReady) {
                                logToFlutter(`⚠️ Book sections not ready after waiting, cannot convert XPath`);
                                location = null;
                            } else {
                                const cfi = await convertXPathToCFI(view, location, logToFlutter);
                                if (cfi && cfi.startsWith('epubcfi')) {
                                    location = cfi;
                                    logToFlutter(`✅ XPath converted to CFI: ${cfi.substring(0, Math.min(50, cfi.length))}...`);
                                } else {
                                    logToFlutter(`⚠️ Conversion returned invalid CFI: ${cfi}`);
                                    location = null;
                                }
                            }
                        }
                    } catch (e) {
                        logToFlutter(`❌ Error converting XPath to CFI: ${e.message}`);
                        logToFlutter(`Stack: ${e.stack}`);
                        // Don't try to navigate with XPath - it will fail
                        location = null;
                    }
                }

                if (location && typeof location === 'string' && location.startsWith('epubcfi')) {
                    try {
                        logToFlutter(`Navigating to CFI location: ${location.substring(0, Math.min(50, location.length))}...`);
                        await view.init({ lastLocation: location, showTextStart: false });
                        logToFlutter(`✅ Book opened and navigated to saved location`);
                    } catch (e) {
                        logToFlutter(`❌ Error navigating to location: ${e.message}`);
                        logToFlutter(`Stack: ${e.stack}`);
                        // Fallback to start if navigation fails
                        try {
                            await view.goTo(0);
                            logToFlutter(`Fell back to start due to navigation error`);
                        } catch (fallbackError) {
                            logToFlutter(`❌ Error falling back to start: ${fallbackError.message}`);
                        }
                    }
                } else {
                    if (location) {
                        logToFlutter(`⚠️ Invalid location format (not CFI), navigating to start. Location: ${typeof location === 'string' ? location.substring(0, Math.min(50, location.length)) : location}`);
                    } else {
                        logToFlutter(`No initial location, navigating to start`);
                    }
                    try {
                        await view.goTo(0);
                    } catch (e) {
                        logToFlutter(`❌ Error navigating to start: ${e.message}`);
                    }
                }
            } else {
                // No saved location, go to start
                logToFlutter(`No initial location, navigating to start`);
                await view.goTo(0);
            }

            logToFlutter('Book opened successfully');

            // On iOS, ensure the renderer is ready and force a reflow to trigger rendering
            // This helps prevent blank screen on first load
            const isIOSCheck = /iPad|iPhone|iPod/.test(navigator.userAgent);
            if (isIOSCheck && view.renderer) {
                try {
                    // Force a reflow by accessing layout properties
                    void view.offsetHeight;
                    void view.renderer.offsetHeight;
                    // Trigger a repaint
                    requestAnimationFrame(() => {
                        requestAnimationFrame(() => {
                            // Reflow forced
                        });
                    });
                } catch (e) {
                    // Ignore reflow errors
                }
            }

            // Calculate location (page numbers) for TOC items based on section sizes
            const toc = view.book?.toc || [];
            const sections = view.book?.sections || [];

            if (toc.length > 0 && sections.length > 0) {
                // Calculate location for sections based on cumulative sizes
                const sizes = sections.map(s => (s.linear !== 'no' && s.size > 0 ? s.size : 0));
                let cumulativeSize = 0;
                const cumulativeSizes = sizes.reduce((acc, size) => {
                    acc.push(cumulativeSize);
                    cumulativeSize += size;
                    return acc;
                }, []);
                const totalSize = cumulativeSizes[cumulativeSizes.length - 1] || 0;
                const sizePerLoc = 1500; // Size per location unit for page calculation

                // Calculate location for each section
                const sectionsWithLocation = sections.map((section, index) => {
                    return {
                        ...section,
                        location: {
                            current: Math.floor(cumulativeSizes[index] / sizePerLoc),
                            next: Math.floor((cumulativeSizes[index] + sizes[index]) / sizePerLoc),
                            total: Math.floor(totalSize / sizePerLoc),
                        }
                    };
                });

                // Create map of section identifiers to section with location
                // Sections can be identified by id, href, or index
                const sectionsMap = new Map();
                sectionsWithLocation.forEach((section, index) => {
                    // Map by id if available
                    if (section.id) {
                        sectionsMap.set(section.id, section);
                    }
                    // Map by href if available (normalize by removing leading slash)
                    if (section.href) {
                        const normalizedHref = section.href.replace(/^\/+/, '');
                        sectionsMap.set(normalizedHref, section);
                        sectionsMap.set(section.href, section);
                    }
                    // Also map by index as fallback
                    sectionsMap.set(`index:${index}`, section);
                });

                // Helper to find section for a TOC item href
                const findSectionForHref = (href) => {
                    if (!href) return null;

                    // Normalize href: remove fragment and leading slash
                    const hrefParts = href.split('#');
                    const baseHref = (hrefParts[0] || href).replace(/^\/+/, '');

                    // Try exact match first
                    let section = sectionsMap.get(baseHref) || sectionsMap.get(href);

                    // If not found, try matching against section hrefs
                    if (!section) {
                        for (const [key, sec] of sectionsMap.entries()) {
                            if (sec.href && (sec.href.endsWith(baseHref) || baseHref.endsWith(sec.href))) {
                                section = sec;
                                break;
                            }
                        }
                    }

                    return section;
                };

                // Recursively add location to TOC items
                const addLocationToToc = (items) => {
                    return items.map((item) => {
                        const result = { ...item };

                        if (item.href) {
                            const section = findSectionForHref(item.href);

                            if (section && section.location) {
                                // Add location when TOC item matches section
                                result.location = section.location;
                            }
                        }

                        // Recursively process subitems
                        if (item.subitems && item.subitems.length > 0) {
                            result.subitems = addLocationToToc(item.subitems);
                        }

                        return result;
                    });
                };

                const tocWithLocation = addLocationToToc(toc);
                logToFlutter(`TOC processed: ${tocWithLocation.length} items with location data`);

                window.flutter_inappwebview?.callHandler('bookLoaded', {
                    toc: tocWithLocation
                });
            } else {
                window.flutter_inappwebview?.callHandler('bookLoaded', {
                    toc: toc
                });
            }
        } catch (e) {
            logToFlutter(`openBook inner error: ${e.message}`);
            logToFlutter(`openBook inner stack: ${e.stack}`);
            console.error('[foliate-bridge] openBook inner error:', e);
            // Try to at least show something
            try {
                await view.goTo(0);
                logToFlutter('Recovered: navigated to start');
            } catch (e2) {
                logToFlutter(`Failed to recover from openBook inner error: ${e2.message}`);
            }
        }
    } catch (e) {
        logToFlutter(`openBook outer error: ${e.message}`);
        logToFlutter(`openBook outer stack: ${e.stack}`);
        console.error('[foliate-bridge] openBook outer error:', e);
        // Try to at least show something
        try {
            const view = await ensureView();
            await view.goTo(0);
            logToFlutter('Recovered from outer error: navigated to start');
        } catch (e2) {
            logToFlutter(`Failed to recover from openBook outer error: ${e2.message}`);
        }
    }
};

/**
 * Navigate to a specific location in the book
 */
const goToLocation = async (options) => {
    const view = await ensureView();
    let { cfi, href, fraction } = options || {};

    try {
        // If cfi is actually an XPath (starts with /body), convert it to CFI first
        if (cfi && typeof cfi === 'string' && cfi.startsWith('/body')) {
            logToFlutter(`Detected XPath in goToLocation, converting: ${cfi.substring(0, Math.min(50, cfi.length))}`);
            try {
                // Wait for book to be available
                let retries = 0;
                const maxRetries = 20;
                while (!view.book && retries < maxRetries) {
                    await new Promise(resolve => setTimeout(resolve, 50));
                    retries++;
                }

                if (!view.book) {
                    logToFlutter(`⚠️ Book not available after ${maxRetries} retries, cannot convert XPath`);
                    throw new Error('Book not available for XPath conversion');
                }

                // Wait for sections to be loaded
                let sectionsReady = false;
                let sectionRetries = 0;
                while (!sectionsReady && sectionRetries < 20) {
                    if (view.book.sections && view.book.sections.length > 0) {
                        sectionsReady = true;
                    } else {
                        await new Promise(resolve => setTimeout(resolve, 50));
                        sectionRetries++;
                    }
                }

                if (!sectionsReady) {
                    logToFlutter(`⚠️ Book sections not ready after waiting, cannot convert XPath`);
                    throw new Error('Book sections not ready for XPath conversion');
                }

                const convertedCfi = await convertXPathToCFI(view, cfi, logToFlutter);
                if (convertedCfi && convertedCfi.startsWith('epubcfi')) {
                    cfi = convertedCfi;
                    logToFlutter(`✅ XPath converted to CFI: ${cfi.substring(0, Math.min(50, cfi.length))}...`);
                } else {
                    logToFlutter(`⚠️ Conversion returned invalid CFI: ${convertedCfi}`);
                    throw new Error('Invalid CFI from XPath conversion');
                }
            } catch (e) {
                logToFlutter(`❌ Error converting XPath to CFI in goToLocation: ${e.message}`);
                throw e; // Re-throw to trigger fallback
            }
        }

        if (cfi) {
            await view.goTo(cfi);
            logToFlutter(`Navigated to CFI: ${cfi.substring(0, 50)}`);
        } else if (href) {
            await view.goTo(href);
            logToFlutter(`Navigated to href: ${href}`);
        } else if (fraction !== undefined) {
            await view.goTo(fraction);
            logToFlutter(`Navigated to fraction: ${fraction}`);
        }
        // Return null explicitly to avoid Promise return type issues with Flutter
        return null;
    } catch (e) {
        logToFlutter(`goToLocation error: ${e.message}`);
        // Return null even on error to avoid Promise return type issues
        return null;
    }
};

/**
 * Navigate to next page
 */
const nextPage = async () => {
    const view = await ensureView();
    try {
        await view.next();
    } catch (e) {
        logToFlutter(`nextPage error: ${e.message}`);
    }
};

/**
 * Navigate to previous page
 */
const prevPage = async () => {
    const view = await ensureView();
    try {
        await view.prev();
    } catch (e) {
        logToFlutter(`prevPage error: ${e.message}`);
    }
};

/**
 * Add an annotation (highlight, underline, etc.)
 */
const addAnnotation = async (annotation) => {
    const view = await ensureView();

    if (!annotation || !annotation.value) {
        logToFlutter('addAnnotation: invalid annotation');
        return;
    }

    try {
        logToFlutter(`Adding annotation: style=${annotation.style}, CFI=${annotation.value.substring(0, 30)}...`);

        // Ensure 'style' field is set
        if (!annotation.style && annotation.type) {
            annotation.style = annotation.type;
            delete annotation.type;
        }

        // Call with small delay to ensure overlayer is ready
        const result = await new Promise((resolve) => {
            setTimeout(async () => {
                try {
                    const res = await view.addAnnotation(annotation);
                    resolve(res);
                } catch (e) {
                    logToFlutter(`addAnnotation async error: ${e.message}`);
                    resolve(null);
                }
            }, 0);
        });

        if (result?.index !== undefined) {
            const index = result.index;

            // Store annotation for tracking
            if (!pendingAnnotations.has(index)) {
                pendingAnnotations.set(index, []);
            }
            pendingAnnotations.get(index).push(annotation);

            logToFlutter(`Annotation stored for index=${index}, overlay created=${overlayCreatedIndices.has(index)}, total pending=${pendingAnnotations.get(index).length}`);

            // CRITICAL FIX: Check if overlay was already created for this section
            // If 'create-overlay' already fired for this section, batch process annotations
            // This handles the case where annotations are restored AFTER the section loads
            if (overlayCreatedIndices.has(index)) {
                logToFlutter(`Overlay already exists for index=${index}, will batch add annotations`);
                // Batch process all pending annotations for this section (similar to create-overlay handler)
                // Use a debounce mechanism to batch multiple annotations together
                if (!window._annotationBatchTimers) {
                    window._annotationBatchTimers = new Map();
                }

                // Clear existing timer for this index
                if (window._annotationBatchTimers.has(index)) {
                    clearTimeout(window._annotationBatchTimers.get(index));
                }

                // Set a new timer to batch process annotations
                const timer = setTimeout(() => {
                    if (pendingAnnotations.has(index)) {
                        const annotations = pendingAnnotations.get(index);
                        logToFlutter(`Batch adding ${annotations.length} annotations for index=${index} (overlay already exists)`);

                        annotations.forEach((ann) => {
                            view.addAnnotation(ann).catch((e) => {
                                if (!e.message?.includes('Range.setStart')) {
                                    logToFlutter(`Error adding annotation to existing overlay: ${e.message}`);
                                }
                            });
                        });

                        // Clear pending annotations after adding
                        pendingAnnotations.delete(index);
                        window._annotationBatchTimers.delete(index);
                        logToFlutter(`Cleared pending annotations for index=${index} (batch processed)`);
                    }
                }, 100); // 100ms delay to batch multiple annotations together

                window._annotationBatchTimers.set(index, timer);
            } else {
                // Overlay hasn't been created yet, add a timeout to retry
                // First retry: 100ms
                setTimeout(() => {
                    if (pendingAnnotations.has(index)) {
                        logToFlutter(`[100ms] Retry: attempting to add annotations for index=${index}`);
                        const annotations = pendingAnnotations.get(index);
                        annotations.forEach((ann) => {
                            view.addAnnotation(ann).catch((e) => {
                                if (!e.message?.includes('Range.setStart')) {
                                    logToFlutter(`Error at 100ms retry: ${e.message}`);
                                }
                            });
                        });
                    }
                }, 100);

                // Second retry: 300ms (for delayed initial load)
                setTimeout(() => {
                    if (pendingAnnotations.has(index)) {
                        logToFlutter(`[300ms] Retry: attempting to add annotations for index=${index}`);
                        const annotations = pendingAnnotations.get(index);
                        annotations.forEach((ann) => {
                            view.addAnnotation(ann).catch((e) => {
                                if (!e.message?.includes('Range.setStart')) {
                                    logToFlutter(`Error at 300ms retry: ${e.message}`);
                                }
                            });
                        });
                    }
                }, 300);
            }
        }

        return result;
    } catch (e) {
        logToFlutter(`addAnnotation error: ${e.message}`);
    }
};

/**
 * Remove an annotation
 */
const removeAnnotation = async (cfiOrAnnotation) => {
    const view = await ensureView();
    try {
        // Handle both string CFI and annotation object (from Flutter JSON)
        // Use addAnnotation with remove=true to delete the annotation
        let annotation;
        if (typeof cfiOrAnnotation === 'string') {
            annotation = { value: cfiOrAnnotation };
        } else if (cfiOrAnnotation && typeof cfiOrAnnotation === 'object') {
            // Use the object as-is (should have 'value' property)
            annotation = cfiOrAnnotation;
        } else {
            logToFlutter('removeAnnotation error: Invalid CFI or annotation object');
            return;
        }

        if (!annotation.value) {
            logToFlutter('removeAnnotation error: Annotation missing value property');
            return;
        }

        // Call addAnnotation with remove=true to delete the annotation
        await view.addAnnotation(annotation, true);
        logToFlutter(`Removed annotation: ${String(annotation.value).substring(0, 30)}...`);
    } catch (e) {
        logToFlutter(`removeAnnotation error: ${e.message}`);
    }
};

/**
 * Generate theme CSS with runtime-configurable variables
 * Uses CSS variables for easy runtime updates without page reload
 */
const generateThemeCSS = (theme) => {
    const { backgroundColor, textColor, fontSize } = theme || {};

    const css = `
        html {
            --theme-bg: ${backgroundColor || '#ffffff'};
            --theme-fg: ${textColor || '#000000'};
            --theme-font-size: ${fontSize || 18}px;
            font-size: ${fontSize || 18}px !important;
        }
        html, body {
            background-color: ${backgroundColor || '#ffffff'} !important;
            color: ${textColor || '#000000'} !important;
            font-size: ${fontSize || 18}px !important;
        }
        /* Ensure all major text elements respect theme */
        p, span, div, h1, h2, h3, h4, h5, h6, li, a, blockquote, section {
            color: ${textColor || '#000000'} !important;
            background-color: inherit;
        }
        body {
            background-color: ${backgroundColor || '#ffffff'} !important;
        }
    `;

    return css;
};

/**
 * Set theme (colors, font size, etc.)
 */
const setTheme = (theme) => {
    currentTheme = theme;

    try {
        const { backgroundColor, textColor, fontSize } = theme || {};

        logToFlutter(`Theme applied: bg=${backgroundColor}, text=${textColor}, size=${fontSize}`);

        // Apply to document root IMMEDIATELY to style the container
        if (backgroundColor) {
            document.documentElement.style.backgroundColor = backgroundColor;
            document.body.style.backgroundColor = backgroundColor;
        }
        if (textColor) {
            document.documentElement.style.color = textColor;
            document.body.style.color = textColor;
        }
        if (fontSize) {
            document.documentElement.style.fontSize = `${fontSize}px`;
            document.body.style.fontSize = `${fontSize}px`;
        }

        // Generate the theme CSS
        const themeCSS = generateThemeCSS(theme);

        // Also create/update a global style element for immediate effect
        let globalThemeStyle = document.getElementById('epub-flutter-global-theme');
        if (!globalThemeStyle) {
            globalThemeStyle = document.createElement('style');
            globalThemeStyle.id = 'epub-flutter-global-theme';
            document.head.appendChild(globalThemeStyle);
        }
        globalThemeStyle.textContent = themeCSS;
        logToFlutter(`Updated global theme style element`);

        // Apply to all currently visible section documents via their style elements
        if (foliateView?.renderer?.getContents) {
            try {
                const contents = foliateView.renderer.getContents?.();
                if (contents && Array.isArray(contents)) {
                    contents.forEach(({ doc }) => {
                        if (doc) {
                            const themeStyleId = 'epub-flutter-theme-style';
                            let themeStyle = doc.getElementById(themeStyleId);
                            if (!themeStyle) {
                                themeStyle = doc.createElement('style');
                                themeStyle.id = themeStyleId;
                                doc.head.appendChild(themeStyle);
                            }
                            themeStyle.textContent = themeCSS;
                        }
                    });
                    logToFlutter(`Updated theme CSS in ${contents.length} visible sections`);
                }
            } catch (e) {
                logToFlutter(`Warning: Could not update visible section styles: ${e.message}`);
            }
        }

        // Apply to all currently loaded sections via the renderer
        if (foliateView?.renderer?.setStyles) {
            foliateView.renderer.setStyles(themeCSS);
            logToFlutter(`Applied theme via renderer.setStyles()`);
        } else {
            logToFlutter(`Warning: foliateView.renderer.setStyles not available yet`);
        }
    } catch (e) {
        logToFlutter(`setTheme error: ${e.message}`);
    }
};

/**
 * Clear the current text selection
 */
const clearSelection = () => {
    try {
        window.getSelection().removeAllRanges();
        logToFlutter('Selection cleared');
    } catch (e) {
        logToFlutter(`clearSelection error: ${e.message}`);
    }
};

/**
 * Set page turn animation duration in milliseconds
 * The paginator uses window.foliateAnimationDuration for animation speed
 */
const setAnimationDuration = async (durationMs) => {
    animationDuration = Math.max(0, Math.min(2000, durationMs)); // Clamp between 0 and 2000ms

    // Set the global variable that paginator.js uses
    window.foliateAnimationDuration = animationDuration;

    logToFlutter(`Animation duration set to ${animationDuration}ms (window.foliateAnimationDuration = ${window.foliateAnimationDuration})`);

    // Verify it was set correctly
    if (window.foliateAnimationDuration !== animationDuration) {
        logToFlutter(`WARNING: window.foliateAnimationDuration mismatch! Expected ${animationDuration}, got ${window.foliateAnimationDuration}`);
    }

    // Note: The 'animated' attribute is now controlled separately via setAnimated()
    // This function only sets the duration, not the attribute itself
};

/**
 * Enable or disable page turn animations by setting/removing the 'animated' attribute
 * on the paginator (renderer) element.
 * @param {boolean} enabled - If true, enables animations; if false, disables them
 */
const setAnimated = async (enabled) => {
    try {
        const view = await ensureView();
        if (view && view.renderer) {
            if (enabled) {
                view.renderer.setAttribute('animated', '');
                logToFlutter('Enabled animations: Set "animated" attribute on paginator element');
            } else {
                view.renderer.removeAttribute('animated');
                logToFlutter('Disabled animations: Removed "animated" attribute from paginator element');
            }
        } else {
            logToFlutter('Warning: Could not set animated attribute - view or renderer not available');
        }
    } catch (e) {
        logToFlutter(`Error setting animated attribute: ${e.message}`);
    }
};

// ============================================================================
// EXPOSE PUBLIC API TO FLUTTER
// ============================================================================

// Wrap bridge initialization in try-catch to ensure errors are logged
try {
    // Expose API globally so Flutter can call it via evaluateJavascript
    // Example: controller.evaluateJavascript('window.everboundReader.openBook({...})')
    window.everboundReader = {
        initReader,
        openBook,
        goToLocation,
        nextPage,
        prevPage,
        addAnnotation,
        removeAnnotation,
        setTheme,
        setAnimationDuration,
        setAnimated,
        clearSelection,
    };

    logToFlutter('✅ Flutter bridge ready! window.everboundReader is exposed');

    // Notify Flutter that the bridge is ready
    try {
        window.flutter_inappwebview?.callHandler('bridgeReady');
    } catch (e) {
        logToFlutter(`Error calling bridgeReady handler: ${e.message}`);
    }
} catch (e) {
    console.error('[foliate-bridge] Error initializing bridge:', e);
    logToFlutter(`❌ CRITICAL: Bridge initialization failed: ${e.message}`);
    logToFlutter(`Stack: ${e.stack}`);
    // Still try to set a minimal bridge object so Flutter can detect the error
    window.everboundReader = {
        initReader: async () => { throw new Error('Bridge not initialized'); },
        openBook: async () => { throw new Error('Bridge not initialized'); },
    };
}

