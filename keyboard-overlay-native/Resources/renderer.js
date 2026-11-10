const keyElements = new Map();
document.querySelectorAll('.key[data-key]').forEach((el) => {
  keyElements.set(el.dataset.key, el);
});

const mouseButtonElements = new Map();
document.querySelectorAll('.key[data-button]').forEach((el) => {
  mouseButtonElements.set(el.dataset.button, el);
});

// Called directly from Swift via webView.evaluateJavaScript — no IPC/bridge needed.
window.handleInputEvent = function (kind, state, value) {
  if (kind === 'key') {
    const el = keyElements.get(value);
    if (el) el.classList.toggle('active', state === 'down');
  } else if (kind === 'mouse') {
    const el = mouseButtonElements.get(value);
    if (el) el.classList.toggle('active', state === 'down');
  }
};

window.setMovable = function (movable) {
  document.body.classList.toggle('movable', movable);
};

window.setAccentColor = function (hex, r, g, b) {
  document.documentElement.style.setProperty('--accent', hex);
  document.documentElement.style.setProperty('--accent-rgb', `${r}, ${g}, ${b}`);
};
