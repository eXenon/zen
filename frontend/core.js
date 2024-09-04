function openWebSocket() {
  const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
  const host = window.location.host;
  const ws = new WebSocket(`${protocol}//${host}/ws`);

  ws.onopen = () => {
    console.log('WebSocket connection established');
    ws.send("ping");
    // Schedule heartbeat every second
    setInterval(() => {
      if (ws.readyState === WebSocket.OPEN) {
        ws.send("ping");
      }
    }, 1000);
  };

  ws.onmessage = (event) => {
    try {
      if (event.data === "pong") {
        // Handle heartbeat response if needed
        return;
      }
      const message = JSON.parse(event.data);
      apply(message);
      setEventListeners(ws);
    } catch (error) {
      console.error('Error parsing WebSocket message:', error);
    }
  };

  ws.onerror = (error) => {
    console.error('WebSocket error:', error);
  };

  ws.onclose = () => {
    console.log('WebSocket connection closed');
  };

  return ws;
}

function apply(message) {
  if (message.body) {
    document.body.innerHTML = message.body;
  } else if (message.diff) {
    applyDiff(message.diff);
  } else {
    console.error('Invalid message format: neither body nor diff found');
  }
}

function applyDiff(diff) {
  for (const change of diff) {
    const element = document.querySelector(change.selector);
    if (element) {
      switch (change.action) {
        case 'update':
          element.outerHTML = change.value;
          break;
        case 'append':
          element.insertAdjacentHTML('beforeend', change.value);
          break;
        case 'prepend':
          element.insertAdjacentHTML('afterbegin', change.value);
          break;
        case 'delete':
          element.remove();
          break;
        case 'updateproperties':
          for (const [key, value] of Object.entries(change.properties)) {
            if (key in element) {
              element[key] = value;
            } else {
              element.setAttribute(key, value);
            }
          }
          break;
        default:
          console.error('Unknown diff action:', change.action);
      }
    } else {
      console.error('Element not found for selector:', change.selector);
    }
  }
}

function payloadForEvent(eventName, event) {
  switch (eventName) {
    case 'click':
      console.log('click event', event);
      return {
        x: event.clientX,
        y: event.clientY
      };
    case 'mouseover':
      return {
        x: event.clientX,
        y: event.clientY
      };
    default:
      return {};
  }
}

function setEventListeners(ws) {
  const targets = document.querySelectorAll('[data-event]');
  for (const target of targets) {
    const eventName = target.getAttribute('data-event');
    const handler = target.getAttribute('data-event-handler');
    const eventHandler = (event) => {
      console.log('Sending event to server:', eventName, event);
      ws.send(JSON.stringify({
        handler: handler,
        name: eventName,
        payload: payloadForEvent(eventName, event)
      }));
    };
    console.log('Setting event listener for', eventName, 'on', target);
    target.addEventListener(eventName, eventHandler);
  }
}

document.addEventListener('DOMContentLoaded', () => {
  const ws = openWebSocket();
  setEventListeners(ws);
});