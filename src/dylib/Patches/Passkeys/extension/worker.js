chrome.runtime.onConnect.addListener((port) => {
  const { origin, pathname: path } = new URL(port.sender.url);
  port.onMessage.addListener((request) => {
    const host = chrome.runtime.connectNative('com.diapatches.passkeys');
    let answered = false;
    host.onMessage.addListener((response) => {
      answered = true;
      port.postMessage(response);
      host.disconnect();
    });
    host.onDisconnect.addListener(() => {
      if (answered) return;
      port.postMessage({ error: { name: 'NotAllowedError', message: chrome.runtime.lastError?.message ?? 'No reply from diapatch' } });
    });
    port.onDisconnect.addListener(() => host.disconnect());
    host.postMessage({ ...request, origin, path });
  });
});
