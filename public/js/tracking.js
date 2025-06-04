const device = navigator.platform || "";
const referrer = new URL(document.referrer);
const sameOrigin = location.hostname === referrer.hostname;
const safeReferrer = sameOrigin ? "" : document.referrer;

const params = new URLSearchParams({ device, safeReferrer });
fetch(`/stats?${params}`, { method: "POST" });
