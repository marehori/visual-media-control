"use strict";

const allowedFonts = ["Segoe UI", "Arial", "Calibri", "Consolas", "Georgia", "Impact", "Trebuchet MS", "Verdana", "Times New Roman"];
const defaults = Object.freeze({
  buttonFunction: "artwork", gridGap: 30,
  iconSize: 56, fillMode: "solid", solidColor: "#FFFFFF", gradientStart: "#FFFFFF",
  gradientEnd: "#7C5CFF", gradientAngle: 45, iconTransparency: 5,
  customIconData: "", customIconName: "",
  shadowEnabled: true, shadowColor: "#000000", shadowOpacity: 32, shadowBlur: 4,
  shadowSpread: 1, shadowOffsetX: 2, shadowOffsetY: 3,
  backdropEnabled: false, backdropColor: "#000000", backdropTransparency: 25,
  backdropSize: 76, backdropBlur: 0,
  textContent: "titleArtist", textFontFamily: "Segoe UI", textSize: 18, textAutoFit: true,
  textFillMode: "solid", textColor: "#FFFFFF", textGradientStart: "#FFFFFF",
  textGradientEnd: "#7C5CFF", textGradientAngle: 45, textTransparency: 0,
  textAlignment: "center", textVerticalAlignment: "center", textBold: true,
  textOutlineEnabled: true, textOutlineColor: "#000000", textOutlineOpacity: 80,
  textOutlineWidth: 1, textShadowEnabled: true, textShadowColor: "#000000",
  textShadowOpacity: 72, textShadowBlur: 2, textShadowOffsetX: 1, textShadowOffsetY: 2
});

let websocket;
let inspectorUUID = "";
const previewParameters = new URLSearchParams(window.location.search);
let actionUUID = previewParameters.get("action") || "";
let actionContext = "";
let settings = { ...defaults };
let saveTimer;
const elements = {};

function clamp(value, minimum, maximum, fallback) {
  const number = Number.parseInt(value, 10);
  return Number.isFinite(number) ? Math.max(minimum, Math.min(maximum, number)) : fallback;
}
function color(value, fallback) {
  return /^#[0-9a-f]{6}$/i.test(String(value || "")) ? String(value).toUpperCase() : fallback;
}
function boolean(value, fallback) {
  if (typeof value === "boolean") return value;
  if (value === "true" || value === 1 || value === "1") return true;
  if (value === "false" || value === 0 || value === "0") return false;
  return fallback;
}
function oneOf(value, allowed, fallback) { return allowed.includes(value) ? value : fallback; }
function isGridAction() { return actionUUID.includes(".grid."); }
function defaultFunctionForAction() {
  if (actionUUID.endsWith(".topleft")) return "previous";
  if (actionUUID.endsWith(".topright")) return "next";
  if (actionUUID.endsWith(".bottomleft")) return "title";
  if (actionUUID.endsWith(".bottomright")) return "playPause";
  return "playPause";
}

function normalize(value) {
  const source = value && typeof value === "object" ? value : {};
  const rawIconData = String(source.customIconData || "");
  const iconData = rawIconData.length <= 1500000 && /^data:image\/png;base64,/i.test(rawIconData)
    ? rawIconData : "";
  return {
    buttonFunction: oneOf(source.buttonFunction, ["artwork", "playPause", "previous", "next", "title"], isGridAction() ? defaultFunctionForAction() : "playPause"),
    gridGap: clamp(source.gridGap, 0, 60, defaults.gridGap),
    iconSize: clamp(source.iconSize, 24, 82, defaults.iconSize),
    fillMode: source.fillMode === "gradient" ? "gradient" : "solid",
    solidColor: color(source.solidColor, defaults.solidColor),
    gradientStart: color(source.gradientStart, defaults.gradientStart),
    gradientEnd: color(source.gradientEnd, defaults.gradientEnd),
    gradientAngle: clamp(source.gradientAngle, 0, 360, defaults.gradientAngle),
    iconTransparency: clamp(source.iconTransparency, 0, 95, defaults.iconTransparency),
    customIconData: iconData, customIconName: String(source.customIconName || "").slice(0, 120),
    shadowEnabled: boolean(source.shadowEnabled, defaults.shadowEnabled),
    shadowColor: color(source.shadowColor, defaults.shadowColor),
    shadowOpacity: clamp(source.shadowOpacity, 0, 100, defaults.shadowOpacity),
    shadowBlur: clamp(source.shadowBlur, 0, 12, defaults.shadowBlur),
    shadowSpread: clamp(source.shadowSpread, 0, 12, defaults.shadowSpread),
    shadowOffsetX: clamp(source.shadowOffsetX, -20, 20, defaults.shadowOffsetX),
    shadowOffsetY: clamp(source.shadowOffsetY, -20, 20, defaults.shadowOffsetY),
    backdropEnabled: boolean(source.backdropEnabled, defaults.backdropEnabled),
    backdropColor: color(source.backdropColor, defaults.backdropColor),
    backdropTransparency: clamp(source.backdropTransparency, 0, 100, defaults.backdropTransparency),
    backdropSize: clamp(source.backdropSize, 45, 100, defaults.backdropSize),
    backdropBlur: clamp(source.backdropBlur, 0, 20, defaults.backdropBlur),
    textContent: oneOf(source.textContent, ["titleArtist", "title", "artist"], defaults.textContent),
    textFontFamily: oneOf(source.textFontFamily, allowedFonts, defaults.textFontFamily),
    textSize: clamp(source.textSize, 10, 36, defaults.textSize),
    textAutoFit: boolean(source.textAutoFit, defaults.textAutoFit),
    textFillMode: source.textFillMode === "gradient" ? "gradient" : "solid",
    textColor: color(source.textColor, defaults.textColor),
    textGradientStart: color(source.textGradientStart, defaults.textGradientStart),
    textGradientEnd: color(source.textGradientEnd, defaults.textGradientEnd),
    textGradientAngle: clamp(source.textGradientAngle, 0, 360, defaults.textGradientAngle),
    textTransparency: clamp(source.textTransparency, 0, 95, defaults.textTransparency),
    textAlignment: oneOf(source.textAlignment, ["left", "center", "right"], defaults.textAlignment),
    textVerticalAlignment: oneOf(source.textVerticalAlignment, ["top", "center", "bottom"], defaults.textVerticalAlignment),
    textBold: boolean(source.textBold, defaults.textBold),
    textOutlineEnabled: boolean(source.textOutlineEnabled, defaults.textOutlineEnabled),
    textOutlineColor: color(source.textOutlineColor, defaults.textOutlineColor),
    textOutlineOpacity: clamp(source.textOutlineOpacity, 0, 100, defaults.textOutlineOpacity),
    textOutlineWidth: clamp(source.textOutlineWidth, 1, 5, defaults.textOutlineWidth),
    textShadowEnabled: boolean(source.textShadowEnabled, defaults.textShadowEnabled),
    textShadowColor: color(source.textShadowColor, defaults.textShadowColor),
    textShadowOpacity: clamp(source.textShadowOpacity, 0, 100, defaults.textShadowOpacity),
    textShadowBlur: clamp(source.textShadowBlur, 0, 8, defaults.textShadowBlur),
    textShadowOffsetX: clamp(source.textShadowOffsetX, -12, 12, defaults.textShadowOffsetX),
    textShadowOffsetY: clamp(source.textShadowOffsetY, -12, 12, defaults.textShadowOffsetY)
  };
}

function setValue(name, value, suffix = "") {
  elements[name].value = value;
  elements[`${name}Value`].value = `${value}${suffix}`;
}

function render() {
  elements.buttonFunction.value = settings.buttonFunction;
  setValue("gridGap", settings.gridGap, " px"); setValue("iconSize", settings.iconSize, "%");
  elements.fillMode.value = settings.fillMode;
  elements.solidColor.value = settings.solidColor; elements.solidColorValue.textContent = settings.solidColor;
  elements.gradientStart.value = settings.gradientStart; elements.gradientEnd.value = settings.gradientEnd;
  setValue("gradientAngle", settings.gradientAngle, "°"); setValue("iconTransparency", settings.iconTransparency, "%");
  const hasCustomIcon = Boolean(settings.customIconData);
  elements.customIconButton.textContent = hasCustomIcon ? "Remove" : "Browse…";
  elements.customIconName.textContent = hasCustomIcon ? (settings.customIconName || "Custom PNG") : "Standard icon";
  elements.customIconPreview.hidden = !hasCustomIcon;
  elements.customIconPreview.src = hasCustomIcon ? settings.customIconData : "";

  elements.shadowEnabled.checked = settings.shadowEnabled;
  elements.shadowColor.value = settings.shadowColor; elements.shadowColorValue.textContent = settings.shadowColor;
  setValue("shadowOpacity", settings.shadowOpacity, "%"); setValue("shadowBlur", settings.shadowBlur, " px");
  setValue("shadowSpread", settings.shadowSpread, " px"); setValue("shadowOffsetX", settings.shadowOffsetX, " px");
  setValue("shadowOffsetY", settings.shadowOffsetY, " px");
  elements.backdropEnabled.checked = settings.backdropEnabled;
  elements.backdropColor.value = settings.backdropColor; elements.backdropColorValue.textContent = settings.backdropColor;
  setValue("backdropTransparency", settings.backdropTransparency, "%"); setValue("backdropSize", settings.backdropSize, "%");
  setValue("backdropBlur", settings.backdropBlur, " px");

  elements.textContent.value = settings.textContent; elements.textFontFamily.value = settings.textFontFamily;
  setValue("textSize", settings.textSize, " px"); elements.textAutoFit.checked = settings.textAutoFit;
  elements.textFillMode.value = settings.textFillMode;
  elements.textColor.value = settings.textColor; elements.textColorValue.textContent = settings.textColor;
  elements.textGradientStart.value = settings.textGradientStart; elements.textGradientEnd.value = settings.textGradientEnd;
  setValue("textGradientAngle", settings.textGradientAngle, "°"); setValue("textTransparency", settings.textTransparency, "%");
  elements.textAlignment.value = settings.textAlignment; elements.textVerticalAlignment.value = settings.textVerticalAlignment;
  elements.textBold.checked = settings.textBold; elements.textOutlineEnabled.checked = settings.textOutlineEnabled;
  elements.textOutlineColor.value = settings.textOutlineColor; elements.textOutlineColorValue.textContent = settings.textOutlineColor;
  setValue("textOutlineOpacity", settings.textOutlineOpacity, "%"); setValue("textOutlineWidth", settings.textOutlineWidth, " px");
  elements.textShadowEnabled.checked = settings.textShadowEnabled;
  elements.textShadowColor.value = settings.textShadowColor; elements.textShadowColorValue.textContent = settings.textShadowColor;
  setValue("textShadowOpacity", settings.textShadowOpacity, "%"); setValue("textShadowBlur", settings.textShadowBlur, " px");
  setValue("textShadowOffsetX", settings.textShadowOffsetX, " px"); setValue("textShadowOffsetY", settings.textShadowOffsetY, " px");

  const activeFunction = isGridAction() ? settings.buttonFunction : "playPause";
  const usesIcon = ["playPause", "previous", "next"].includes(activeFunction);
  const usesText = activeFunction === "title";
  elements.buttonFunctionSection.hidden = !isGridAction(); elements.gridSection.hidden = !isGridAction();
  elements.iconSection.hidden = !usesIcon; elements.shadowSection.hidden = !usesIcon;
  elements.backdropSection.hidden = !usesIcon; elements.textSection.hidden = !usesText;
  elements.textOutlineSection.hidden = !usesText; elements.textShadowSection.hidden = !usesText;
  elements.standardIconFillOptions.hidden = hasCustomIcon;
  elements.solidOptions.hidden = settings.fillMode !== "solid";
  elements.gradientOptions.hidden = settings.fillMode !== "gradient";
  elements.shadowOptions.hidden = !settings.shadowEnabled; elements.backdropOptions.hidden = !settings.backdropEnabled;
  elements.textSolidOptions.hidden = settings.textFillMode !== "solid";
  elements.textGradientOptions.hidden = settings.textFillMode !== "gradient";
  elements.textOutlineOptions.hidden = !settings.textOutlineEnabled;
  elements.textShadowOptions.hidden = !settings.textShadowEnabled;
  elements.settings.hidden = false;
}

function sendSettings() {
  if (!websocket || websocket.readyState !== WebSocket.OPEN) return;
  websocket.send(JSON.stringify({ event: "setSettings", context: inspectorUUID, payload: settings }));
  websocket.send(JSON.stringify({ event: "sendToPlugin", action: actionUUID, context: inspectorUUID, payload: { actionContext, settings } }));
}
function scheduleSave() { clearTimeout(saveTimer); saveTimer = setTimeout(sendSettings, 80); }

function readControls() {
  settings = normalize({ ...settings,
    buttonFunction: elements.buttonFunction.value, gridGap: elements.gridGap.value,
    iconSize: elements.iconSize.value, fillMode: elements.fillMode.value,
    solidColor: elements.solidColor.value, gradientStart: elements.gradientStart.value,
    gradientEnd: elements.gradientEnd.value, gradientAngle: elements.gradientAngle.value,
    iconTransparency: elements.iconTransparency.value, shadowEnabled: elements.shadowEnabled.checked,
    shadowColor: elements.shadowColor.value, shadowOpacity: elements.shadowOpacity.value,
    shadowBlur: elements.shadowBlur.value, shadowSpread: elements.shadowSpread.value,
    shadowOffsetX: elements.shadowOffsetX.value, shadowOffsetY: elements.shadowOffsetY.value,
    backdropEnabled: elements.backdropEnabled.checked, backdropColor: elements.backdropColor.value,
    backdropTransparency: elements.backdropTransparency.value, backdropSize: elements.backdropSize.value,
    backdropBlur: elements.backdropBlur.value, textContent: elements.textContent.value,
    textFontFamily: elements.textFontFamily.value, textSize: elements.textSize.value,
    textAutoFit: elements.textAutoFit.checked, textFillMode: elements.textFillMode.value,
    textColor: elements.textColor.value, textGradientStart: elements.textGradientStart.value,
    textGradientEnd: elements.textGradientEnd.value, textGradientAngle: elements.textGradientAngle.value,
    textTransparency: elements.textTransparency.value, textAlignment: elements.textAlignment.value,
    textVerticalAlignment: elements.textVerticalAlignment.value, textBold: elements.textBold.checked,
    textOutlineEnabled: elements.textOutlineEnabled.checked, textOutlineColor: elements.textOutlineColor.value,
    textOutlineOpacity: elements.textOutlineOpacity.value, textOutlineWidth: elements.textOutlineWidth.value,
    textShadowEnabled: elements.textShadowEnabled.checked, textShadowColor: elements.textShadowColor.value,
    textShadowOpacity: elements.textShadowOpacity.value, textShadowBlur: elements.textShadowBlur.value,
    textShadowOffsetX: elements.textShadowOffsetX.value, textShadowOffsetY: elements.textShadowOffsetY.value
  });
  render(); scheduleSave();
}

function readFileAsDataUrl(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(String(reader.result || ""));
    reader.onerror = () => reject(new Error("The PNG could not be read."));
    reader.readAsDataURL(file);
  });
}
function resizePng(dataUrl) {
  return new Promise((resolve, reject) => {
    const image = new Image();
    image.onload = () => {
      const canvas = document.createElement("canvas"); canvas.width = 288; canvas.height = 288;
      const context = canvas.getContext("2d"); context.clearRect(0, 0, 288, 288);
      const scale = Math.min(288 / image.naturalWidth, 288 / image.naturalHeight);
      const width = Math.max(1, Math.round(image.naturalWidth * scale));
      const height = Math.max(1, Math.round(image.naturalHeight * scale));
      context.drawImage(image, Math.round((288 - width) / 2), Math.round((288 - height) / 2), width, height);
      resolve(canvas.toDataURL("image/png"));
    };
    image.onerror = () => reject(new Error("The selected file is not a valid PNG."));
    image.src = dataUrl;
  });
}
async function importCustomIcon(file) {
  if (!file) return;
  if (!file.name.toLowerCase().endsWith(".png") || (file.type && file.type !== "image/png")) {
    elements.customIconName.textContent = "Please select a PNG file"; return;
  }
  if (file.size > 2 * 1024 * 1024) {
    elements.customIconName.textContent = "PNG must be 2 MB or smaller"; return;
  }
  try {
    const resized = await resizePng(await readFileAsDataUrl(file));
    settings = normalize({ ...settings, customIconData: resized, customIconName: file.name });
    render(); scheduleSave();
  } catch (error) {
    elements.customIconName.textContent = error.message || "The PNG could not be loaded";
  } finally { elements.customIconFile.value = ""; }
}

function bindControls() {
  [
    "settings", "buttonFunctionSection", "buttonFunction", "gridSection", "gridGap", "gridGapValue",
    "iconSection", "customIconPreview", "customIconFile", "customIconButton", "customIconName",
    "standardIconFillOptions", "iconSize", "iconSizeValue", "fillMode", "solidOptions", "solidColor",
    "solidColorValue", "gradientOptions", "gradientStart", "gradientEnd", "gradientAngle", "gradientAngleValue",
    "iconTransparency", "iconTransparencyValue", "shadowSection", "shadowEnabled", "shadowOptions", "shadowColor",
    "shadowColorValue", "shadowOpacity", "shadowOpacityValue", "shadowBlur", "shadowBlurValue", "shadowSpread",
    "shadowSpreadValue", "shadowOffsetX", "shadowOffsetXValue", "shadowOffsetY", "shadowOffsetYValue",
    "backdropSection", "backdropEnabled", "backdropOptions", "backdropColor", "backdropColorValue",
    "backdropTransparency", "backdropTransparencyValue", "backdropSize", "backdropSizeValue", "backdropBlur",
    "backdropBlurValue", "textSection", "textContent", "textFontFamily", "textSize", "textSizeValue", "textAutoFit",
    "textFillMode", "textSolidOptions", "textColor", "textColorValue", "textGradientOptions", "textGradientStart",
    "textGradientEnd", "textGradientAngle", "textGradientAngleValue", "textTransparency", "textTransparencyValue",
    "textAlignment", "textVerticalAlignment", "textBold", "textOutlineSection", "textOutlineEnabled",
    "textOutlineOptions", "textOutlineColor", "textOutlineColorValue", "textOutlineOpacity", "textOutlineOpacityValue",
    "textOutlineWidth", "textOutlineWidthValue", "textShadowSection", "textShadowEnabled", "textShadowOptions",
    "textShadowColor", "textShadowColorValue", "textShadowOpacity", "textShadowOpacityValue", "textShadowBlur",
    "textShadowBlurValue", "textShadowOffsetX", "textShadowOffsetXValue", "textShadowOffsetY",
    "textShadowOffsetYValue", "reset", "githubLink"
  ].forEach(name => { elements[name] = document.getElementById(name); });

  [
    "buttonFunction", "gridGap", "iconSize", "fillMode", "solidColor", "gradientStart", "gradientEnd", "gradientAngle",
    "iconTransparency", "shadowEnabled", "shadowColor", "shadowOpacity", "shadowBlur", "shadowSpread", "shadowOffsetX",
    "shadowOffsetY", "backdropEnabled", "backdropColor", "backdropTransparency", "backdropSize", "backdropBlur",
    "textContent", "textFontFamily", "textSize", "textAutoFit", "textFillMode", "textColor", "textGradientStart",
    "textGradientEnd", "textGradientAngle", "textTransparency", "textAlignment", "textVerticalAlignment", "textBold",
    "textOutlineEnabled", "textOutlineColor", "textOutlineOpacity", "textOutlineWidth", "textShadowEnabled",
    "textShadowColor", "textShadowOpacity", "textShadowBlur", "textShadowOffsetX", "textShadowOffsetY"
  ].forEach(name => {
    elements[name].addEventListener("input", readControls);
    elements[name].addEventListener("change", readControls);
  });

  elements.customIconButton.addEventListener("click", () => {
    if (settings.customIconData) {
      settings = normalize({ ...settings, customIconData: "", customIconName: "" });
      render(); scheduleSave();
    } else { elements.customIconFile.click(); }
  });
  elements.customIconFile.addEventListener("change", () => importCustomIcon(elements.customIconFile.files[0]));
  elements.githubLink.addEventListener("click", event => {
    event.preventDefault();
    const url = elements.githubLink.href;
    if (websocket && websocket.readyState === WebSocket.OPEN) {
      websocket.send(JSON.stringify({ event: "openUrl", payload: { url } }));
    } else {
      window.open(url, "_blank");
    }
  });
  const previewFunction = previewParameters.get("buttonFunction");
  if (previewFunction) settings = normalize({ buttonFunction: previewFunction });
  elements.reset.addEventListener("click", () => {
    settings = normalize({ buttonFunction: defaultFunctionForAction() }); render(); scheduleSave();
  });
  render();
}

document.addEventListener("DOMContentLoaded", bindControls);

function connectElgatoStreamDeckSocket(port, uuid, registerEvent, applicationInfo, actionInfo) {
  inspectorUUID = uuid;
  let info = {};
  try { info = JSON.parse(actionInfo || "{}"); } catch (_) { info = {}; }
  actionUUID = info.action || "com.marehori.nowplaying.playpause";
  actionContext = info.context || "";
  settings = normalize(info.payload && info.payload.settings);
  if (document.readyState !== "loading") render();
  websocket = new WebSocket(`ws://127.0.0.1:${port}`);
  websocket.addEventListener("open", () => {
    websocket.send(JSON.stringify({ event: registerEvent, uuid }));
    websocket.send(JSON.stringify({ event: "getSettings", context: inspectorUUID }));
  });
  websocket.addEventListener("message", event => {
    let message;
    try { message = JSON.parse(event.data); } catch (_) { return; }
    if (message.event === "didReceiveSettings" && message.payload) {
      settings = normalize(message.payload.settings); render();
    }
  });
}

window.connectElgatoStreamDeckSocket = connectElgatoStreamDeckSocket;
