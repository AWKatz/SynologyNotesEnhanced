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
    'hr',
  ]);
  var ALLOWED_GLOBAL_ATTRS = new Set(['style', 'class']);
  var ALLOWED_TAG_ATTRS = {
    input: new Set(['type', 'src']),
    hr: new Set(['id']),
  };
  var ALLOWED_STYLE_PROPS = new Set([
    'font-family', 'color', 'background-color', 'text-decoration', 'width', 'height',
  ]);
  var ALLOWED_TEXT_DECORATION = new Set(['line-through']);
  var FONT_SIZE_CLASS = /^syno-fontsize-[a-z]+$/;
  var CHECKBOX_CLASS = /^syno-notestation-editor-checkbox( syno-notestation-editor-checkbox-checked)?$/;
  var CHECKBOX_SRC = 'webman/3rdparty/NoteStation/images/transparent.gif';

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
  }

  // --- init -----------------------------------------------------------
  document.execCommand('styleWithCSS', false, false); // keep bold/italic/underline as <b>/<i>/<u>, not styled spans

  var dirtyTimer = null;
  editor.addEventListener('input', function () {
    sanitize(editor);
    if (dirtyTimer) clearTimeout(dirtyTimer);
    dirtyTimer = setTimeout(notifyDirty, 250);
  });

  editor.addEventListener('paste', function (e) {
    e.preventDefault();
    var text = (e.clipboardData || window.clipboardData).getData('text/plain');
    document.execCommand('insertText', false, text);
  });

  // Tap-to-toggle checkboxes.
  editor.addEventListener('click', function (e) {
    var target = e.target;
    if (target && target.tagName === 'INPUT' &&
        target.classList.contains('syno-notestation-editor-checkbox')) {
      e.preventDefault();
      target.classList.toggle('syno-notestation-editor-checkbox-checked');
      notifyDirty();
    }
  });

  // --- Flutter bridge ---------------------------------------------------
  window.setContent = function (html) {
    editor.innerHTML = html;
    sanitize(editor);
  };

  window.getContent = function () {
    sanitize(editor);
    return editor.innerHTML;
  };

  window.setDarkMode = function (dark) {
    document.body.classList.toggle('dark', !!dark);
  };

  // --- formatting commands ----------------------------------------------
  window.cmdBold = function () { document.execCommand('bold'); afterEdit(); };
  window.cmdItalic = function () { document.execCommand('italic'); afterEdit(); };
  window.cmdUnderline = function () { document.execCommand('underline'); afterEdit(); };
  window.cmdSuperscript = function () { document.execCommand('superscript'); afterEdit(); };
  window.cmdSubscript = function () { document.execCommand('subscript'); afterEdit(); };
  window.cmdOrderedList = function () { document.execCommand('insertOrderedList'); afterEdit(); };
  window.cmdUnorderedList = function () { document.execCommand('insertUnorderedList'); afterEdit(); };

  window.cmdHeading = function (level) {
    document.execCommand('formatBlock', false, '<H' + level + '>');
    afterEdit();
  };
  window.cmdParagraph = function () {
    document.execCommand('formatBlock', false, '<DIV>');
    afterEdit();
  };

  // Native execCommand('strikeThrough'/'foreColor') emit <strike>/<font> —
  // neither is in the confirmed vocabulary — so these wrap the selection in
  // the exact <span style="..."> shape the real fixture uses instead.
  window.cmdStrikethrough = function () {
    wrapSelectionStyle('text-decoration', 'line-through');
    afterEdit();
  };
  window.cmdFontColor = function (hex) {
    wrapSelectionStyle('color', hex);
    afterEdit();
  };
  window.cmdHighlight = function (hex) {
    wrapSelectionStyle('background-color', hex);
    afterEdit();
  };
  window.cmdFontFamily = function (name) {
    wrapSelectionStyle('font-family', name);
    afterEdit();
  };

  window.cmdInsertCheckbox = function () {
    document.execCommand('insertHTML', false,
      '<input class="syno-notestation-editor-checkbox" src="' + CHECKBOX_SRC + '" type="image" />');
    afterEdit();
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
    document.execCommand('insertHTML', false, html);
    afterEdit();
  };

  window.cmdInsertDivider = function () {
    document.execCommand('insertHTML', false, '<hr/>');
    afterEdit();
  };
})();
