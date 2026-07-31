(function () {
  'use strict';

  // Mirrors lib/core/rich_html/rich_html_schema.dart — the confirmed
  // NoteStation-preserved HTML vocabulary. Keep the two in sync.
  var ALLOWED_TAGS = new Set([
    'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
    'div', 'p',
    'b', 'i', 'u', 'sup', 'sub', 'span',
    'ol', 'ul', 'li',
    'input',
    'table', 'tbody', 'tr', 'td',
    'hr', 'br',
    'a', 'img',
  ]);
  var ALLOWED_GLOBAL_ATTRS = new Set(['style', 'class']);
  var ALLOWED_TAG_ATTRS = {
    input: new Set(['type', 'src']),
    hr: new Set(['id']),
    a: new Set(['href']),
    // width/height: confirmed present on a real NAS-saved image (TinyMCE
    // sets them for sizing) though absent from the original capture's
    // request payload — kept in sync with rich_html_schema.dart.
    img: new Set(['class', 'src', 'border', 'ref', 'adjust', 'width', 'height']),
  };
  var ALLOWED_STYLE_PROPS = new Set([
    'font-family', 'color', 'background-color', 'text-decoration', 'width', 'height', 'text-align',
    // Generated only by cmdCropImage/cmdFontSize below, never arbitrary
    // user CSS — see rich_html_schema.dart's matching comments for the
    // risk rationale.
    'object-fit', 'object-position', 'font-size',
  ]);
  var ALLOWED_TEXT_DECORATION = new Set(['line-through']);
  // Only 'center' was directly captured, but left/right/justify are exactly
  // what cmdAlign's own justifyLeft/Center/Right produce below — a
  // controlled, known output set, not arbitrary user CSS.
  var ALLOWED_TEXT_ALIGN = new Set(['left', 'center', 'right', 'justify']);
  var ALLOWED_OBJECT_FIT = new Set(['cover', 'contain', 'fill', 'none', 'scale-down']);
  var ALLOWED_OBJECT_POSITION = new Set(['center']);
  // Matches rich_html_schema.dart's _fontSizePx bound (6-150px).
  var FONT_SIZE_PX = /^([6-9]|[1-9][0-9]|1[0-4][0-9]|150)px$/;
  // Hyphen included: real captured class is "syno-fontsize-x-large", which
  // the old (no-hyphen) pattern rejected.
  var FONT_SIZE_CLASS = /^syno-fontsize-[a-z-]+$/;
  var CHECKBOX_CLASS = /^syno-notestation-editor-checkbox( syno-notestation-editor-checkbox-checked)?$/;
  var IMAGE_CLASS = /^syno-notestation-image-object$/;
  // VERIFIED (2026-07-25 HAR capture): a saved image tag never carries the
  // real picture in `src` — same placeholder trick as CHECKBOX_SRC below,
  // except here it's the *real* NAS-relative path the capture showed (not a
  // local data URI), because this exact string is what actually gets
  // persisted to the note content sent to the NAS — see getContent()'s
  // save-time swap, which is what writes this in, keyed off the `ref`
  // attribute that carries the real link instead.
  var IMAGE_SRC = 'webman/3rdparty/NoteStation/images/transparent.gif';
  // The stock NAS-relative path (kept here only as a comment for context:
  // 'webman/3rdparty/NoteStation/images/transparent.gif') never resolves in
  // this app's isolated local WebView, so the browser paints its own
  // "broken image" glyph on top of — and regardless of — the CSS checkbox
  // styling in editor.css. An inline, always-loadable transparent pixel
  // avoids that entirely; the checkbox's actual look still comes purely
  // from CSS (border/background/::after), same as before.
  //
  // Must be a PNG, not a GIF, here: a 1x1 GIF's transparency depends on a
  // Graphic Control Extension setting the transparent-color flag — easy to
  // get subtly wrong and end up with an opaquely-colored pixel instead
  // (which then paints over the CSS background/checkmark). PNG alpha
  // transparency has no such ambiguity.
  // Generated and pixel-verified locally (Bitmap(1,1) filled with
  // Color.FromArgb(0,0,0,0), re-decoded to confirm alpha=0) rather than
  // recalled from memory — a previous attempt here looked plausible but
  // decoded to an opaque black pixel instead.
  var CHECKBOX_SRC = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAALSURBVBhXY2AAAgAABQABqtXIUQAAAABJRU5ErkJggg==';

  var editor = document.getElementById('editor');

  function sanitizeElement(el) {
    var tag = el.tagName.toLowerCase();
    if (!ALLOWED_TAGS.has(tag)) {
      // Unwrap: keep the content, drop the disallowed wrapper.
      var parent = el.parentNode;
      if (!parent) return;
      while (el.firstChild) parent.insertBefore(el.firstChild, el);
      parent.removeChild(el);
      return;
    }

    Array.prototype.slice.call(el.attributes).forEach(function (attr) {
      var name = attr.name.toLowerCase();
      var tagAllowed = ALLOWED_TAG_ATTRS[tag] && ALLOWED_TAG_ATTRS[tag].has(name);
      if (!ALLOWED_GLOBAL_ATTRS.has(name) && !tagAllowed) {
        el.removeAttribute(attr.name);
      }
    });

    if (tag === 'input') {
      if (el.getAttribute('type') !== 'image') {
        el.remove();
        return;
      }
      el.setAttribute('src', CHECKBOX_SRC);
      var cls = el.getAttribute('class') || '';
      if (!CHECKBOX_CLASS.test(cls)) {
        el.setAttribute('class', 'syno-notestation-editor-checkbox');
      }
    }

    if (tag === 'span') {
      var scls = el.getAttribute('class');
      if (scls && !FONT_SIZE_CLASS.test(scls)) el.removeAttribute('class');
    }

    if (tag === 'img') {
      // Unlike checkbox <input>'s CHECKBOX_SRC, `src` is deliberately NOT
      // forced back to IMAGE_SRC here — sanitizeElement runs continuously
      // while editing (every keystroke, plus setContent), and forcing a
      // shared constant is only harmless for checkboxes because their glyph
      // is the same for every checkbox. Each image's live-preview src is
      // different per element and needs to survive repeated sanitize passes;
      // only getContent() (see below) swaps it to IMAGE_SRC, and only on a
      // detached clone, right at serialization time.
      var icls = el.getAttribute('class') || '';
      if (!IMAGE_CLASS.test(icls)) el.remove();
    }

    var style = el.getAttribute('style');
    if (style) {
      var kept = [];
      style.split(';').forEach(function (decl) {
        var idx = decl.indexOf(':');
        if (idx === -1) return;
        var prop = decl.substring(0, idx).trim().toLowerCase();
        var value = decl.substring(idx + 1).trim();
        if (!ALLOWED_STYLE_PROPS.has(prop)) return;
        if (prop === 'text-decoration' && !ALLOWED_TEXT_DECORATION.has(value.toLowerCase())) return;
        if (prop === 'text-align' && !ALLOWED_TEXT_ALIGN.has(value.toLowerCase())) return;
        if (prop === 'object-fit' && !ALLOWED_OBJECT_FIT.has(value.toLowerCase())) return;
        if (prop === 'object-position' && !ALLOWED_OBJECT_POSITION.has(value.toLowerCase())) return;
        if (prop === 'font-size' && !FONT_SIZE_PX.test(value.toLowerCase())) return;
        if (value) kept.push(prop + ': ' + value);
      });
      if (kept.length) el.setAttribute('style', kept.join('; ') + ';');
      else el.removeAttribute('style');
    }
  }

  function sanitize(root) {
    // Bottom-up so unwrapping a disallowed parent doesn't skip its children.
    var all = root.querySelectorAll('*');
    for (var i = all.length - 1; i >= 0; i--) sanitizeElement(all[i]);
  }

  function notifyDirty() {
    if (window.flutter_inappwebview) {
      window.flutter_inappwebview.callHandler('onDirty');
    }
  }

  function wrapSelectionStyle(prop, value) {
    var sel = window.getSelection();
    if (!sel.rangeCount || sel.isCollapsed) return;
    var range = sel.getRangeAt(0);
    var span = document.createElement('span');
    span.style.setProperty(prop, value);
    try {
      range.surroundContents(span);
    } catch (e) {
      var frag = range.extractContents();
      span.appendChild(frag);
      range.insertNode(span);
    }
    sel.removeAllRanges();
    var newRange = document.createRange();
    newRange.selectNodeContents(span);
    sel.addRange(newRange);
  }

  function afterEdit() {
    sanitize(editor);
    notifyDirty();
    // A command may have resized/moved the selected image (resize, crop,
    // placement) — keep the selection ring in sync with it.
    updateImageSelectionRing();
  }

  // --- init -----------------------------------------------------------
  document.execCommand('styleWithCSS', false, false); // keep bold/italic/underline as <b>/<i>/<u>, not styled spans
  document.execCommand('defaultParagraphSeparator', false, 'div'); // Enter always starts a new <div>, matching the block-per-line shape elsewhere in the schema

  // Flutter's toolbar buttons live outside the WebView; tapping one moves
  // native focus away from #editor, which drops or collapses its selection
  // before the resulting cmd* call runs. Track the last real selection
  // inside the editor and restore it (and focus) right before applying any
  // toolbar-triggered command, so formatting lands on what the user picked
  // instead of requiring them to reselect.
  var lastRange = null;
  document.addEventListener('selectionchange', function () {
    var sel = window.getSelection();
    if (!sel.rangeCount) return;
    var range = sel.getRangeAt(0);
    var el = range.commonAncestorContainer;
    el = el.nodeType === 1 ? el : el.parentElement;
    if (el && editor.contains(el)) {
      lastRange = range.cloneRange();
      updateTextSelectionHighlight(lastRange);
    }
  });

  function restoreSelection() {
    editor.focus();
    if (!lastRange) return;
    var sel = window.getSelection();
    sel.removeAllRanges();
    sel.addRange(lastRange);
  }

  // Persistent text-selection highlight (see editor.css's matching
  // ::highlight rule): the CSS Custom Highlight API renders independently
  // of the native Selection object, so it stays visible even once focus
  // moves to the Flutter toolbar and the browser would otherwise stop
  // painting the native selection. Feature-checked — silently does nothing
  // on engines without it, same as not having this visual at all.
  var TEXT_SELECTION_HIGHLIGHT = 'syno-editor-selection';
  function updateTextSelectionHighlight(range) {
    if (!window.CSS || !CSS.highlights || typeof Highlight === 'undefined') return;
    if (!range || range.collapsed) {
      CSS.highlights.delete(TEXT_SELECTION_HIGHLIGHT);
      return;
    }
    CSS.highlights.set(TEXT_SELECTION_HIGHLIGHT, new Highlight(range));
  }

  // Selected-image indicator: an absolutely-positioned <div> appended to
  // <body> — deliberately OUTSIDE #editor, and therefore never touched by
  // sanitize() or included in getContent()'s output. Marking the <img>
  // itself (a class or style) was considered and rejected: sanitizeElement
  // requires an EXACT class match on <img> (see IMAGE_CLASS), so any extra
  // class would get the whole element deleted, and inline styles outside
  // ALLOWED_STYLE_PROPS get silently stripped on the very next sanitize()
  // pass (e.g. right after applying a toolbar command) — this sidesteps
  // both risks entirely.
  var imageSelectionRing = null;
  function ensureSelectionRing() {
    if (!imageSelectionRing) {
      imageSelectionRing = document.createElement('div');
      imageSelectionRing.className = 'syno-image-selection-ring';
      document.body.appendChild(imageSelectionRing);
    }
    return imageSelectionRing;
  }
  function updateImageSelectionRing() {
    var ring = ensureSelectionRing();
    if (!activeImage) {
      ring.style.display = 'none';
      return;
    }
    var rect = activeImage.getBoundingClientRect();
    ring.style.display = 'block';
    ring.style.left = (rect.left + window.scrollX) + 'px';
    ring.style.top = (rect.top + window.scrollY) + 'px';
    ring.style.width = rect.width + 'px';
    ring.style.height = rect.height + 'px';
  }
  window.addEventListener('scroll', updateImageSelectionRing, true);
  window.addEventListener('resize', updateImageSelectionRing);

  // Wraps a toolbar-triggered command: reclaim focus/selection first, run
  // the command, then sanitize + notify. Use this (not a bare execCommand)
  // for every window.cmd* the toolbar calls.
  function withSelection(fn) {
    restoreSelection();
    fn();
    afterEdit();
  }

  var dirtyTimer = null;
  editor.addEventListener('input', function () {
    tryInlineMarkdownShorthand();
    sanitize(editor);
    if (dirtyTimer) clearTimeout(dirtyTimer);
    dirtyTimer = setTimeout(notifyDirty, 250);
  });

  editor.addEventListener('paste', function (e) {
    e.preventDefault();
    var text = (e.clipboardData || window.clipboardData).getData('text/plain');
    if (!text) return;
    // Multi-line paste (a whole note/document) gets real block structure --
    // one element per line, headings/lists/hr recognized. A single-line
    // paste is almost always inline content dropped mid-sentence/mid-
    // paragraph, so it must NOT be wrapped in its own <div> (that would
    // split the surrounding line in two); it only gets inline markdown
    // (bold/italic/code/etc.) applied and is inserted right at the caret.
    var hasNewline = /\r|\n/.test(text);
    var html = hasNewline
      ? markdownToHtml(text)
      : inlineMarkdown(escapeHtml(text));
    document.execCommand('insertHTML', false, html);
    afterEdit();
  });

  // Tab has no native contenteditable behavior worth keeping (default is
  // focus navigation, not indentation). Inside a list item, nest/un-nest it
  // (stays within the existing ol/ul/li vocabulary); elsewhere, insert
  // literal indentation whitespace (plain text, needs no schema support).
  editor.addEventListener('keydown', function (e) {
    if (e.key !== 'Tab') return;
    e.preventDefault();
    var sel = window.getSelection();
    var li = sel.rangeCount ? closestTag(sel.getRangeAt(0).startContainer, 'li') : null;
    if (li) {
      document.execCommand(e.shiftKey ? 'outdent' : 'indent');
    } else if (!e.shiftKey) {
      // Plain spaces collapse under normal HTML whitespace rules -- nbsp
      // stays visible without needing any new schema/style support.
      document.execCommand('insertText', false, '    ');
    }
    afterEdit();
  });

  function closestTag(node, tag) {
    var el = node.nodeType === 1 ? node : node.parentElement;
    while (el && el !== editor) {
      if (el.tagName && el.tagName.toLowerCase() === tag) return el;
      el = el.parentElement;
    }
    return null;
  }

  // --- markdown shorthand -------------------------------------------------
  // Typing (or pasting) common markdown syntax auto-converts to the
  // equivalent rich element, matching the "smart formatting as you type"
  // behavior of editors like Notion/Slack. Deliberately limited to
  // constructs already in the confirmed-preserved schema (ALLOWED_TAGS/
  // ALLOWED_STYLE_PROPS above) -- fenced code blocks and blockquotes aren't
  // supported here yet because that HTML vocabulary hasn't been verified
  // against a real NAS capture (see CAPTURE-CHECKLIST.md); wire those in
  // once that capture lands.

  function closestBlock(node) {
    var el = node.nodeType === 1 ? node : node.parentElement;
    while (el && el !== editor) {
      var tag = el.tagName && el.tagName.toLowerCase();
      if (tag === 'div' || tag === 'p' || tag === 'li' || /^h[1-6]$/.test(tag || '')) return el;
      el = el.parentElement;
    }
    return null;
  }

  function escapeHtml(s) {
    return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }

  // Applied to already-escaped text (see escapeHtml) -- delimiter characters
  // are untouched by escaping, so wrapping them in real tags afterward can't
  // introduce any markup the user didn't ask for. Order matters: code spans
  // first (so ** inside `code` is never touched), bold before single-* italic
  // (so **x** doesn't also get read as *x* on its inner asterisk pair).
  // Single-underscore italic (_x_) is deliberately NOT supported -- it
  // misfires constantly on snake_case identifiers in a general notes app.
  function inlineMarkdown(escaped) {
    escaped = escaped.replace(/`([^`]+)`/g, function (m, p1) {
      return '<span style="font-family: monospace; background-color: rgba(127,127,127,0.18)">' + p1 + '</span>';
    });
    escaped = escaped.replace(/~~([^~]+)~~/g, '<span style="text-decoration: line-through">$1</span>');
    escaped = escaped.replace(/\*\*([^*]+)\*\*/g, '<b>$1</b>');
    escaped = escaped.replace(/__([^_]+)__/g, '<b>$1</b>');
    escaped = escaped.replace(/\*([^*]+)\*/g, '<i>$1</i>');
    // http(s)/mailto only -- no javascript:/data: links from pasted text.
    escaped = escaped.replace(/\[([^\]]+)\]\((https?:\/\/[^)\s]+|mailto:[^)\s]+)\)/g,
      '<a href="$2">$1</a>');
    return escaped;
  }

  // Converts a plain-text (possibly multi-line, markdown-flavored) paste
  // into schema-safe HTML. Headings/lists/hr are recognized per-line; every
  // other non-blank line becomes its own <div> (matching defaultParagraph
  // Separator), consistent with how a plain typed line is stored.
  function markdownToHtml(text) {
    var lines = text.split(/\r\n|\r|\n/);
    var parts = [];
    var listType = null;
    var listItems = [];

    function flushList() {
      if (!listType) return;
      var items = listItems.map(function (li) { return '<li>' + inlineMarkdown(li) + '</li>'; }).join('');
      parts.push('<' + listType + '>' + items + '</' + listType + '>');
      listType = null;
      listItems = [];
    }

    lines.forEach(function (line) {
      var heading = /^(#{1,6})\s+(.*)$/.exec(line);
      var ul = /^[-*+]\s+(.*)$/.exec(line);
      var ol = /^\d+\.\s+(.*)$/.exec(line);
      var hr = /^(-{3,}|\*{3,}|_{3,})$/.test(line.trim());

      if (heading) {
        flushList();
        var level = heading[1].length;
        parts.push('<h' + level + '>' + inlineMarkdown(escapeHtml(heading[2])) + '</h' + level + '>');
      } else if (hr) {
        flushList();
        parts.push('<hr/>');
      } else if (ul) {
        if (listType !== 'ul') flushList();
        listType = 'ul';
        listItems.push(escapeHtml(ul[1]));
      } else if (ol) {
        if (listType !== 'ol') flushList();
        listType = 'ol';
        listItems.push(escapeHtml(ol[1]));
      } else if (line.trim() === '') {
        flushList();
      } else {
        flushList();
        parts.push('<div>' + inlineMarkdown(escapeHtml(line)) + '</div>');
      }
    });
    flushList();
    return parts.join('');
  }

  // Live-typing inline shorthand: checked on every 'input' event, but only
  // ever acts when the caret sits at the very end of a plain Text node --
  // i.e. right after the character just typed -- so it only ever reacts to
  // what the user is actively typing, never to unrelated text elsewhere in
  // the note. Each pattern is $-anchored for the same reason.
  var INLINE_MD_PATTERNS = [
    {
      re: /`([^`]+)`$/,
      make: function (m) {
        var el = document.createElement('span');
        el.style.fontFamily = 'monospace';
        el.style.backgroundColor = 'rgba(127,127,127,0.18)';
        el.textContent = m[1];
        return el;
      },
    },
    {
      re: /~~([^~]+)~~$/,
      make: function (m) {
        var el = document.createElement('span');
        el.style.textDecoration = 'line-through';
        el.textContent = m[1];
        return el;
      },
    },
    {
      re: /\*\*([^*]+)\*\*$/,
      make: function (m) { var el = document.createElement('b'); el.textContent = m[1]; return el; },
    },
    {
      re: /__([^_]+)__$/,
      make: function (m) { var el = document.createElement('b'); el.textContent = m[1]; return el; },
    },
    // Tried after bold, so a just-completed **bold** never also matches here.
    {
      re: /\*([^*]+)\*$/,
      make: function (m) { var el = document.createElement('i'); el.textContent = m[1]; return el; },
    },
    {
      re: /\[([^\]]+)\]\((https?:\/\/[^)\s]+|mailto:[^)\s]+)\)$/,
      make: function (m) {
        var el = document.createElement('a');
        el.setAttribute('href', m[2]);
        el.textContent = m[1];
        return el;
      },
    },
  ];

  function tryInlineMarkdownShorthand() {
    var sel = window.getSelection();
    if (!sel.rangeCount || !sel.isCollapsed) return;
    var range = sel.getRangeAt(0);
    var node = range.startContainer;
    if (node.nodeType !== 3 || range.startOffset !== node.length) return;
    if (!editor.contains(node)) return;

    var text = node.textContent;
    for (var i = 0; i < INLINE_MD_PATTERNS.length; i++) {
      var m = INLINE_MD_PATTERNS[i].re.exec(text);
      if (!m) continue;

      var el = INLINE_MD_PATTERNS[i].make(m);
      var replaceRange = document.createRange();
      replaceRange.setStart(node, m.index);
      replaceRange.setEnd(node, node.length);
      replaceRange.deleteContents();
      replaceRange.insertNode(el);

      // Land the caret in a fresh empty text node right after, so typing
      // continues as plain text instead of inside the new element.
      var after = document.createTextNode('');
      el.parentNode.insertBefore(after, el.nextSibling);
      var caret = document.createRange();
      caret.setStart(after, 0);
      caret.collapse(true);
      sel.removeAllRanges();
      sel.addRange(caret);
      return;
    }
  }

  // Block-level shorthand: "# ", "## ", ... "###### ", "- "/"* ", "1. " at
  // the very start of an otherwise-empty line convert the whole line to the
  // matching block type, consuming the triggering space as the marker's own
  // delimiter (not inserted as content) -- same convention most markdown-
  // aware editors use.
  editor.addEventListener('keydown', function (e) {
    if (e.key !== ' ') return;
    var sel = window.getSelection();
    if (!sel.rangeCount || !sel.isCollapsed) return;
    var range = sel.getRangeAt(0);
    var block = closestBlock(range.startContainer);
    if (!block) return;

    var pre = document.createRange();
    pre.setStart(block, 0);
    pre.setEnd(range.startContainer, range.startOffset);
    var textBeforeCaret = pre.toString();

    var heading = /^(#{1,6})$/.exec(textBeforeCaret);
    var ul = /^[-*]$/.test(textBeforeCaret);
    var ol = /^\d+\.$/.test(textBeforeCaret);
    if (!heading && !ul && !ol) return;

    e.preventDefault();
    var markerRange = document.createRange();
    markerRange.setStart(block, 0);
    markerRange.setEnd(range.startContainer, range.startOffset);
    markerRange.deleteContents();

    if (heading) {
      document.execCommand('formatBlock', false, '<H' + heading[1].length + '>');
    } else if (ul) {
      document.execCommand('insertUnorderedList');
    } else {
      document.execCommand('insertOrderedList');
    }
    afterEdit();
  });

  // "---"/"***"/"___" alone on a line, followed by Enter, becomes a divider
  // -- mirrors cmdInsertDivider's own <hr/>, just triggered by typing.
  editor.addEventListener('keydown', function (e) {
    if (e.key !== 'Enter') return;
    var sel = window.getSelection();
    if (!sel.rangeCount || !sel.isCollapsed) return;
    var block = closestBlock(sel.getRangeAt(0).startContainer);
    if (!block || !/^(-{3,}|\*{3,}|_{3,})$/.test(block.textContent.trim())) return;

    e.preventDefault();
    var hr = document.createElement('hr');
    var newLine = document.createElement('div');
    newLine.innerHTML = '<br>';
    block.replaceWith(hr);
    hr.parentNode.insertBefore(newLine, hr.nextSibling);

    var r = document.createRange();
    r.setStart(newLine, 0);
    r.collapse(true);
    sel.removeAllRanges();
    sel.addRange(r);
    afterEdit();
  });

  // Tap-to-toggle checkboxes; tap-to-select for the image align/resize/crop
  // commands below (activeImage is whatever <img> was last clicked, cleared
  // on clicking anywhere else — those commands silently no-op with nothing
  // selected, same as the table row/column commands do outside a table).
  var activeImage = null;
  editor.addEventListener('click', function (e) {
    var target = e.target;
    if (target && target.tagName === 'INPUT' &&
        target.classList.contains('syno-notestation-editor-checkbox')) {
      e.preventDefault();
      target.classList.toggle('syno-notestation-editor-checkbox-checked');
      notifyDirty();
      return;
    }
    activeImage = (target && target.tagName === 'IMG') ? target : null;
    if (activeImage) updateTextSelectionHighlight(null);
    updateImageSelectionRing();
  });

  // --- Flutter bridge ---------------------------------------------------
  window.setContent = function (html) {
    editor.innerHTML = html;
    sanitize(editor);
  };

  window.getContent = function () {
    sanitize(editor);
    // Swap each image's live-preview `src` (a data: URI, or a previously-
    // resolved display URL for an already-saved image) back to the real
    // placeholder path before serializing — on a detached clone, so the
    // live editor keeps showing the actual picture unaffected. This is the
    // save-time half of the same trick checkbox <input>s use unconditionally
    // in sanitizeElement; images need it deferred to here instead (see the
    // comment on IMAGE_SRC) because the "real" value differs per element.
    var clone = editor.cloneNode(true);
    var imgs = clone.querySelectorAll('img[ref]');
    for (var i = 0; i < imgs.length; i++) {
      imgs[i].setAttribute('src', IMAGE_SRC);
    }
    return clone.innerHTML;
  };

  window.setDarkMode = function (dark) {
    document.body.classList.toggle('dark', !!dark);
  };

  // Drives --accent (see editor.css) so the checked-checkbox fill
  // matches whichever accent color the user picked in Settings.
  window.setAccentColor = function (hex) {
    document.documentElement.style.setProperty('--accent', hex);
  };

  // Overrides editor.css's --bg/--fg (only approximations of the app's
  // real surface/onSurface colors — close, but not an exact match) with
  // the Flutter theme's actual values, so there's no visible color seam
  // when switching between the read view and this WebView. Set on body
  // (not documentElement) so it wins over the body.dark stylesheet rule —
  // custom properties declared directly on an element always beat ones
  // only inherited from an ancestor, regardless of the ancestor rule's
  // specificity.
  window.setSurfaceColors = function (bgHex, fgHex) {
    document.body.style.setProperty('--bg', bgHex);
    document.body.style.setProperty('--fg', fgHex);
  };

  // --- formatting commands ----------------------------------------------
  window.cmdBold = function () { withSelection(function () { document.execCommand('bold'); }); };
  window.cmdItalic = function () { withSelection(function () { document.execCommand('italic'); }); };
  window.cmdUnderline = function () { withSelection(function () { document.execCommand('underline'); }); };
  window.cmdSuperscript = function () { withSelection(function () { document.execCommand('superscript'); }); };
  window.cmdSubscript = function () { withSelection(function () { document.execCommand('subscript'); }); };
  window.cmdOrderedList = function () { withSelection(function () { document.execCommand('insertOrderedList'); }); };
  window.cmdUnorderedList = function () { withSelection(function () { document.execCommand('insertUnorderedList'); }); };

  window.cmdHeading = function (level) {
    withSelection(function () { document.execCommand('formatBlock', false, '<H' + level + '>'); });
  };
  window.cmdParagraph = function () {
    withSelection(function () { document.execCommand('formatBlock', false, '<DIV>'); });
  };

  // execCommand's justify* commands set `style="text-align: ..."` on the
  // enclosing block natively — exactly the shape the 2026-07-25 HAR capture
  // verified round-trips, no manual span-wrapping needed (unlike
  // strikethrough/color below).
  window.cmdAlign = function (direction) {
    var cmd = direction === 'center' ? 'justifyCenter'
      : direction === 'right' ? 'justifyRight'
      : direction === 'justify' ? 'justifyFull'
      : 'justifyLeft';
    withSelection(function () { document.execCommand(cmd); });
  };

  // Native execCommand('strikeThrough'/'foreColor') emit <strike>/<font> —
  // neither is in the confirmed vocabulary — so these wrap the selection in
  // the exact <span style="..."> shape the real fixture uses instead.
  window.cmdStrikethrough = function () {
    withSelection(function () { wrapSelectionStyle('text-decoration', 'line-through'); });
  };
  window.cmdFontColor = function (hex) {
    withSelection(function () { wrapSelectionStyle('color', hex); });
  };
  window.cmdHighlight = function (hex) {
    withSelection(function () { wrapSelectionStyle('background-color', hex); });
  };
  window.cmdFontFamily = function (name) {
    withSelection(function () { wrapSelectionStyle('font-family', name); });
  };
  // [px] is a plain number (e.g. 18, not "18px") — user-typed, not a preset;
  // see FONT_SIZE_PX for the accepted range.
  window.cmdFontSize = function (px) {
    withSelection(function () { wrapSelectionStyle('font-size', px + 'px'); });
  };

  // Native execCommand('createLink') also sets target/rel/class attributes
  // on some engines — the capture showed a bare href only, so this builds
  // the <a> by hand instead, same reasoning as wrapSelectionStyle above.
  window.cmdInsertLink = function (url) {
    withSelection(function () {
      var sel = window.getSelection();
      if (!sel.rangeCount || sel.isCollapsed) return;
      var range = sel.getRangeAt(0);
      var a = document.createElement('a');
      a.setAttribute('href', url);
      try {
        range.surroundContents(a);
      } catch (e) {
        var frag = range.extractContents();
        a.appendChild(frag);
        range.insertNode(a);
      }
      sel.removeAllRanges();
    });
  };

  // [dataUri] is the picked image's own bytes, shown live until the next
  // getContent() swaps it to IMAGE_SRC for saving (see above). [ref] must be
  // the same value Dart's upload call passes as the new attachment's `ref`,
  // so the two can be correlated once the upload completes.
  window.cmdInsertImage = function (dataUri, ref) {
    withSelection(function () {
      document.execCommand('insertHTML', false,
        '<img class="syno-notestation-image-object" src="' + dataUri +
        '" ref="' + ref + '" border="0" adjust="true" />');
    });
  };

  // Placement: reuses cmdAlign's own justify* commands (same verified
  // text-align-on-the-enclosing-block shape) by first selecting the whole
  // image node, so "align" behaves identically whether the selection is
  // text or a picture.
  window.cmdAlignImage = function (direction) {
    if (!activeImage) return;
    var range = document.createRange();
    range.selectNode(activeImage);
    var sel = window.getSelection();
    sel.removeAllRanges();
    sel.addRange(range);
    lastRange = range.cloneRange();
    window.cmdAlign(direction);
  };

  var IMAGE_SIZE_PRESETS = { small: 200, medium: 400, large: 800 };

  // Sets width/height attributes (not style) — matches the shape a real
  // NAS-saved, TinyMCE-sized image already uses (see rich_html_schema.dart's
  // img attribute comment). 'original' removes both, reverting to the
  // image's natural size (editor.css's max-width:100% still applies).
  window.cmdResizeImage = function (preset) {
    if (!activeImage) return;
    withSelection(function () {
      if (preset === 'original') {
        activeImage.removeAttribute('width');
        activeImage.removeAttribute('height');
        return;
      }
      var targetWidth = IMAGE_SIZE_PRESETS[preset];
      if (!targetWidth) return;
      var naturalW = activeImage.naturalWidth || targetWidth;
      var naturalH = activeImage.naturalHeight || targetWidth;
      activeImage.setAttribute('width', String(targetWidth));
      activeImage.setAttribute('height',
        String(Math.round(targetWidth * (naturalH / naturalW))));
    });
  };

  // height/width ratio for each preset's crop frame.
  var IMAGE_CROP_RATIOS = { square: 1, portrait: 4 / 3, landscape: 3 / 4, wide: 9 / 16 };

  // Simple, non-draggable crop: fixes the display box to the given aspect
  // ratio and uses object-fit:cover (+ centered object-position) so the
  // image fills that box without distortion, cropping whatever overflows —
  // display-only, the underlying uploaded file/bytes are never touched.
  window.cmdCropImage = function (preset) {
    if (!activeImage) return;
    withSelection(function () {
      if (preset === 'none') {
        activeImage.style.objectFit = '';
        activeImage.style.objectPosition = '';
        return;
      }
      var ratio = IMAGE_CROP_RATIOS[preset];
      if (!ratio) return;
      var w = parseInt(activeImage.getAttribute('width'), 10) ||
        activeImage.naturalWidth || IMAGE_SIZE_PRESETS.medium;
      activeImage.setAttribute('width', String(w));
      activeImage.setAttribute('height', String(Math.round(w * ratio)));
      activeImage.style.objectFit = 'cover';
      activeImage.style.objectPosition = 'center';
    });
  };

  window.cmdInsertCheckbox = function () {
    withSelection(function () {
      document.execCommand('insertHTML', false,
        '<input class="syno-notestation-editor-checkbox" src="' + CHECKBOX_SRC + '" type="image" />');
    });
  };

  window.cmdInsertTable = function (rows, cols) {
    rows = rows || 3;
    cols = cols || 3;
    var html = '<div><table style="width: 240px; height: 120px;"><tbody>';
    for (var r = 0; r < rows; r++) {
      html += '<tr>';
      for (var c = 0; c < cols; c++) html += '<td>&nbsp;</td>';
      html += '</tr>';
    }
    html += '</tbody></table></div>';
    withSelection(function () { document.execCommand('insertHTML', false, html); });
  };

  window.cmdInsertDivider = function () {
    withSelection(function () { document.execCommand('insertHTML', false, '<hr/>'); });
  };

  // --- table row/column editing ------------------------------------------
  function currentCell() {
    if (!lastRange) return null;
    return closestTag(lastRange.startContainer, 'td');
  }

  function cellIndex(cell) {
    return Array.prototype.indexOf.call(cell.parentElement.children, cell);
  }

  window.cmdTableInsertRowAbove = function () {
    withSelection(function () {
      var cell = currentCell();
      if (!cell) return;
      var row = cell.parentElement;
      var cols = row.children.length;
      var newRow = document.createElement('tr');
      for (var i = 0; i < cols; i++) newRow.appendChild(makeCell());
      row.parentElement.insertBefore(newRow, row);
    });
  };

  window.cmdTableInsertRowBelow = function () {
    withSelection(function () {
      var cell = currentCell();
      if (!cell) return;
      var row = cell.parentElement;
      var cols = row.children.length;
      var newRow = document.createElement('tr');
      for (var i = 0; i < cols; i++) newRow.appendChild(makeCell());
      row.parentElement.insertBefore(newRow, row.nextSibling);
    });
  };

  window.cmdTableDeleteRow = function () {
    withSelection(function () {
      var cell = currentCell();
      if (!cell) return;
      var row = cell.parentElement;
      var tbody = row.parentElement;
      if (tbody.children.length <= 1) {
        // Last row — remove the whole table rather than leave an empty shell.
        var table = closestTag(tbody, 'table');
        if (table) table.parentElement.removeChild(table);
      } else {
        tbody.removeChild(row);
      }
      // The cached range pointed inside the now-removed row — drop it so the
      // next toolbar command doesn't try to restore a detached selection.
      lastRange = null;
    });
  };

  window.cmdTableDeleteTable = function () {
    withSelection(function () {
      var cell = currentCell();
      if (!cell) return;
      var table = closestTag(cell, 'table');
      if (!table) return;
      table.parentElement.removeChild(table);
      // The cached range pointed inside the now-removed table.
      lastRange = null;
    });
  };

  window.cmdTableInsertColumnLeft = function () { insertColumn(true); };
  window.cmdTableInsertColumnRight = function () { insertColumn(false); };

  function insertColumn(left) {
    withSelection(function () {
      var cell = currentCell();
      if (!cell) return;
      var idx = cellIndex(cell);
      var table = closestTag(cell, 'table');
      if (!table) return;
      var rows = table.querySelectorAll('tr');
      for (var i = 0; i < rows.length; i++) {
        var ref = rows[i].children[left ? idx : idx + 1] || null;
        rows[i].insertBefore(makeCell(), ref);
      }
    });
  }

  window.cmdTableDeleteColumn = function () {
    withSelection(function () {
      var cell = currentCell();
      if (!cell) return;
      var idx = cellIndex(cell);
      var table = closestTag(cell, 'table');
      if (!table) return;
      var rows = table.querySelectorAll('tr');
      if (rows.length && rows[0].children.length <= 1) {
        table.parentElement.removeChild(table);
        lastRange = null;
        return;
      }
      for (var i = 0; i < rows.length; i++) {
        var c = rows[i].children[idx];
        if (c) rows[i].removeChild(c);
      }
      // The cached range pointed inside a now-removed cell in this column.
      lastRange = null;
    });
  };

  function makeCell() {
    var td = document.createElement('td');
    td.innerHTML = '&nbsp;';
    return td;
  }
})();
