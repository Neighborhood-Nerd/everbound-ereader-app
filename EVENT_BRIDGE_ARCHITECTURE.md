# Event Bridge Architecture: From Foliate.js to Flutter

## Overview

This document explains how events from foliate-js files (like `reader.js` and `view.js`) are exposed to Flutter through a bridge pattern.

---

## The Three-Layer Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  LAYER 1: FOLIATE-JS (Web)                                      │
│  ─────────────────────────────────────────────────────────────  │
│                                                                  │
│  reader.js, view.js, and other foliate JS files emit DOM        │
│  events on the foliate-view custom element:                     │
│                                                                  │
│    view.addEventListener('show-annotation', (e) => {           │
│        const annotation = this.annotationsByValue.get(e.detail)  │
│        if (annotation.note) alert(annotation.note)              │
│    })                                                            │
│                                                                  │
│  These events are the "source of truth" from foliate-js         │
└─────────────────────────┬───────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│  LAYER 2: FLUTTER-BRIDGE (JavaScript/Bridge)                    │
│  ─────────────────────────────────────────────────────────────  │
│                                                                  │
│  File: assets/foliate/flutter-bridge.js                         │
│                                                                  │
│  1. Listen to foliate-js events on the view element:            │
│                                                                  │
│     view.addEventListener('show-annotation', (event) => {       │
│         const { value } = event.detail || {};                   │
│         logToFlutter(`📌 show-annotation fired...`);             │
│                                                                  │
│         // Relay to Flutter via the InAppWebView bridge:        │
│         window.flutter_inappwebview?.callHandler(               │
│             'showAnnotation',                                   │
│             { value, detail: event.detail }                     │
│         );                                                      │
│     });                                                          │
│                                                                  │
│  2. Log the event for debugging                                 │
│  3. Call Flutter handler with serialized event data             │
│                                                                  │
└─────────────────────────┬───────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│  LAYER 3: FLUTTER (Dart/Native)                                 │
│  ─────────────────────────────────────────────────────────────  │
│                                                                  │
│  File: lib/widgets/foliate_webview.dart                         │
│                                                                  │
│  1. Register JavaScript handler in onWebViewCreated:            │
│                                                                  │
│     controller.addJavaScriptHandler(                            │
│         handlerName: 'showAnnotation',  // Must match Layer 2    │
│         callback: (data) {                                      │
│             final detail = Map<String, dynamic>.from(           │
│                 data as Map<dynamic, dynamic>                   │
│             );                                                  │
│             widget.onAnnotationEvent?.call(detail);             │
│         }                                                       │
│     );                                                          │
│                                                                  │
│  2. Parse the received data                                     │
│  3. Call the Flutter callback (if provided)                     │
│                                                                  │
│  4. In consumer code (e.g., ReaderScreen):                      │
│                                                                  │
│     FoliateWebView(                                             │
│         ...                                                     │
│         onAnnotationEvent: (detail) {                           │
│             final value = detail['value'] as String?;           │
│             _showAnnotationNote(value);  // Your logic here      │
│         },                                                      │
│     )                                                           │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Step-by-Step Flow: "Show Annotation" Event Example

### 1️⃣ User clicks on annotation in the book (Web/JS)
```javascript
// In foliate/view.js or overlayer.js
// When user clicks on a highlighted annotation
element.addEventListener('click', () => {
    const event = new CustomEvent('show-annotation', {
        detail: { value: 'epubcfi(/6/4[intro]!/4/2,/1:0,/1:50)' }
    });
    view.dispatchEvent(event);
});
```

### 2️⃣ Flutter-bridge captures and relays (JavaScript Bridge)
```javascript
// In flutter-bridge.js (LAYER 2)
view.addEventListener('show-annotation', (event) => {
    const { value } = event.detail || {};
    logToFlutter(`📌 show-annotation event FIRED for value=${value?.substring(0, 30)}...`);
    
    // Send to Flutter
    window.flutter_inappwebview?.callHandler('showAnnotation', {
        value,
        detail: event.detail
    });
});
```

### 3️⃣ Flutter receives and processes (Dart/Native)
```dart
// In foliate_webview.dart (LAYER 3)
controller.addJavaScriptHandler(
    handlerName: 'showAnnotation',  // ← Must match callHandler name in Layer 2
    callback: (data) {
        try {
            final detail = Map<String, dynamic>.from(
                data as Map<dynamic, dynamic>
            );
            widget.onAnnotationEvent?.call(detail);
        } catch (_) {}
        return null;
    },
);
```

### 4️⃣ Consumer uses the callback (Your code in ReaderScreen)
```dart
// In reader_screen.dart
FoliateWebView(
    controller: _foliateController,
    epubFilePath: _bookPath,
    onAnnotationEvent: (detail) {
        final value = detail['value'] as String?;
        _showAnnotationNote(value);
    },
)
```

---

## Pattern: Adding a New Event

To expose **any** foliate-js event to Flutter, follow this 3-layer pattern:

### 1. Listen in flutter-bridge.js (LAYER 2)
```javascript
view.addEventListener('your-event-name', (event) => {
    logToFlutter(`Event fired: ${JSON.stringify(event.detail)}`);
    
    window.flutter_inappwebview?.callHandler('yourEventName', {
        // Include whatever data the event provides
        ...event.detail,
        // Or wrap it:
        detail: event.detail
    });
});
```

### 2. Register handler in foliate_webview.dart (LAYER 3)
```dart
controller.addJavaScriptHandler(
    handlerName: 'yourEventName',  // camelCase matches JavaScript
    callback: (data) {
        try {
            final detail = Map<String, dynamic>.from(
                data as Map<dynamic, dynamic>
            );
            widget.onYourEvent?.call(detail);  // or custom callback name
        } catch (_) {}
        return null;
    },
);
```

### 3. Add callback parameter to FoliateWebView (if needed)
```dart
class FoliateWebView extends StatefulWidget {
    final void Function(Map<String, dynamic>)? onYourEvent;
    
    const FoliateWebView({
        ...
        this.onYourEvent,
    });
}
```

### 4. Use in consumer code
```dart
FoliateWebView(
    onYourEvent: (detail) {
        // Handle the event
    },
)
```

---

## Key Rules & Best Practices

### ✅ DO:
1. **Use event names from reader.js as source of truth** (foliate-js pattern)
2. **Log in the bridge** for debugging (use `logToFlutter()`)
3. **Use consistent naming**:
   - foliate-js: `kebab-case` (e.g., `'show-annotation'`)
   - JavaScript bridge: `camelCase` (e.g., `showAnnotation`)
   - Flutter handler: `camelCase` (e.g., `onShowAnnotation`)
4. **Handle data type conversions** (JavaScript object → Dart Map)
5. **Add null-safety checks** in try-catch blocks

### ❌ DON'T:
1. **Don't modify foliate-js event structures** (they come from the foliate-js library)
2. **Don't skip logging** - it's critical for debugging
3. **Don't hardcode handler names** - keep them consistent
4. **Don't forget to serialize/deserialize data** correctly
5. **Don't add handlers without testing** both JavaScript and Flutter sides

---

## Example: Complete "show-annotation" Implementation

### Step 1: flutter-bridge.js (already done ✅)
```javascript
view.addEventListener('show-annotation', (event) => {
    const { value } = event.detail || {};
    logToFlutter(`📌 show-annotation event FIRED for value=${value?.substring(0, 30)}...`);
    
    window.flutter_inappwebview?.callHandler('showAnnotation', {
        value,
        detail: event.detail
    });
});
```

### Step 2: foliate_webview.dart (already done ✅)
```dart
controller.addJavaScriptHandler(
    handlerName: 'showAnnotation',
    callback: (data) {
        try {
            if (data is Map) {
                final detail = Map<String, dynamic>.from(data as Map<dynamic, dynamic>);
                widget.onAnnotationEvent?.call(detail);
            } else if (data is List && data.isNotEmpty && data.first is Map) {
                final detail = Map<String, dynamic>.from(data.first as Map<dynamic, dynamic>);
                widget.onAnnotationEvent?.call(detail);
            }
        } catch (_) {}
        return null;
    },
);
```

### Step 3: Use in ReaderScreen
```dart
FoliateWebView(
    controller: _foliateController,
    onAnnotationEvent: (detail) {
        final value = detail['value'] as String?;
        if (value != null) {
            _showAnnotationNote(value);  // Show popup, toast, etc.
        }
    },
)
```

---

## Event Flow Diagram (ASCII)

```
User clicks annotation
         │
         ▼
┌─────────────────────────────────────┐
│ Foliate-JS Event Fires              │
│ 'show-annotation' on view element   │
└────────────┬────────────────────────┘
             │
             ▼
┌─────────────────────────────────────┐
│ flutter-bridge.js                   │
│ Listens: view.addEventListener()    │
│ Sends: flutter_inappwebview.        │
│        callHandler('showAnnotation')│
└────────────┬────────────────────────┘
             │
             ▼
┌─────────────────────────────────────┐
│ Flutter InAppWebView Bridge         │
│ Receives JavaScript handler call    │
│ Triggers registered callback        │
└────────────┬────────────────────────┘
             │
             ▼
┌─────────────────────────────────────┐
│ foliate_webview.dart                │
│ JavaScript handler 'showAnnotation' │
│ Calls: widget.onAnnotationEvent()   │
└────────────┬────────────────────────┘
             │
             ▼
┌─────────────────────────────────────┐
│ Your Code (reader_screen.dart)      │
│ Processes annotation data           │
│ Shows note to user                  │
└─────────────────────────────────────┘
```

---

## Debugging Checklist

When an event isn't reaching Flutter:

1. **Check flutter-bridge.js**
   - Is the event listener registered? (`view.addEventListener(...)`)
   - Is `logToFlutter()` printing? (Check console)
   - Is `callHandler()` being called?

2. **Check foliate_webview.dart**
   - Is the handler registered? (`addJavaScriptHandler(...)`)
   - Is the handler name correct? (camelCase)
   - Does it match the JavaScript `callHandler()` name?

3. **Check your consumer code**
   - Is the callback provided? (e.g., `onAnnotationEvent: (detail) {...}`)
   - Is the callback null-safe?

4. **Check the data**
   - Use `debugPrint()` in Flutter to log received data
   - Check browser console for JavaScript errors
   - Use `logToFlutter()` to see what's being sent

---

## Reference: Existing Events

| Event Name | Source | Foliate-JS | Flutter Handler | Notes |
|------------|--------|-----------|-----------------|-------|
| `'relocate'` | view.js | `'relocate'` | `relocated` | Page navigation |
| `'load'` | view.js | `'load'` | `sectionLoaded` | Section loaded |
| `'draw-annotation'` | view.js | `'draw-annotation'` | (handled in bridge) | Annotation rendering |
| `'create-overlay'` | view.js | `'create-overlay'` | (handled in bridge) | Overlay created |
| `'show-annotation'` | reader.js | `'show-annotation'` | `showAnnotation` | **NEW: Annotation clicked** |

---

## Summary

To expose a foliate-js event to Flutter:

1. **Find the event** in foliate-js (e.g., `'show-annotation'` in reader.js)
2. **Add listener in flutter-bridge.js** (Layer 2) → calls `window.flutter_inappwebview.callHandler()`
3. **Register handler in foliate_webview.dart** (Layer 3) → uses `addJavaScriptHandler()`
4. **Add callback to FoliateWebView** (if needed) → for consumer code
5. **Use in your code** (e.g., ReaderScreen) → pass callback and handle event

This pattern ensures clean separation of concerns and makes it easy to surface any foliate-js event to Flutter! 🎉




