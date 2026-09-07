// shared/devices.js — EXPERIMENTAL / FASE 0 / NOT PRODUCT CODE
// Device enumeration helpers. Device *labels* are only populated by the
// browser after at least one getUserMedia() permission has been granted —
// callers should request a throwaway permission first if they need labels
// before the user picks a real source.

export async function listDevices() {
  const devices = await navigator.mediaDevices.enumerateDevices();
  return {
    audioinput: devices.filter((d) => d.kind === "audioinput"),
    audiooutput: devices.filter((d) => d.kind === "audiooutput"),
    videoinput: devices.filter((d) => d.kind === "videoinput"),
  };
}

export function fillSelect(selectEl, deviceList, { includeDefault = true, defaultLabel = "Default" } = {}) {
  const previousValue = selectEl.value;
  selectEl.innerHTML = "";
  if (includeDefault) {
    const opt = document.createElement("option");
    opt.value = "";
    opt.textContent = defaultLabel;
    selectEl.appendChild(opt);
  }
  deviceList.forEach((d, i) => {
    const opt = document.createElement("option");
    opt.value = d.deviceId;
    opt.textContent = d.label || `${d.kind} ${i + 1} (${d.deviceId.slice(0, 8)})`;
    selectEl.appendChild(opt);
  });
  if ([...selectEl.options].some((o) => o.value === previousValue)) {
    selectEl.value = previousValue;
  }
}

export async function requestLabelPermission() {
  // A throwaway getUserMedia call so enumerateDevices() returns real labels.
  // Immediately stops the tracks — this is not the actual capture used later.
  try {
    const s = await navigator.mediaDevices.getUserMedia({ audio: true });
    s.getTracks().forEach((t) => t.stop());
    return true;
  } catch (e) {
    return false;
  }
}

export function supportsSetSinkId() {
  return typeof HTMLMediaElement !== "undefined" && "setSinkId" in HTMLMediaElement.prototype;
}
