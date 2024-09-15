const LISTENERS = {}
const LOCK = false
const ZEN_NODES = {};
const ttdebugger = timeTravelDebugger()

function initialValuesSet() {
  // Why do I even need this?
  const inputs = document.querySelectorAll('input[type="text"]');
  for (const input of inputs) {
    input.value = input.getAttribute('value')
  }
}

function openWebSocket() {
  const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
  const host = window.location.host;
  const ws = new WebSocket(`${protocol}//${host}/ws`);
  const HEARTBEAT_INTERVAL = 10000;

  ws.onopen = () => {
    console.log('WebSocket connection established');
    //ws.send("ping");
    ws.send("init+" + document.body.getAttribute('data-zen-id'));
    // Schedule heartbeat every second
    // setInterval(() => {
    //   if (ws.readyState === WebSocket.OPEN) {
    //     ws.send("ping");
    //   }
    // }, HEARTBEAT_INTERVAL);
  };

  ws.onmessage = (event) => {
    try {
      if (event.data === "pong") {
        // Handle heartbeat response if needed
        return;
      }
      const message = JSON.parse(event.data);
      ttdebugger.addMessage(message)
      apply(ws, message);
      ttdebugger.addState(document.getElementById('root').innerHTML);
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

function apply(ws, message) {
  if (message.title !== undefined) {
    document.title = message.title
  }
  if (message.body) {
    const root = document.getElementById('root');
    root.innerHTML = '';
    root.appendChild(jsonToDOM(ws, message.body));
  } else if (message.diff) {
    applyDiff(ws, message.diff);
  } else {
    console.error('Invalid message format: neither body nor diff found');
  }
}

function isProtectedAttribute(attr) {
  return attr.slice(0, 8) == "data-zen-"
}

function applyDiff(ws, diff) {
  for (const change of diff) {
    const element = ZEN_NODES[change.selector];
    if (element) {
      switch (change.action) {
        case 'update':
          element.replaceWith(jsonToDOM(ws, change.value));
          break;
        case 'append':
          element.appendChild(jsonToDOM(ws, change.value));
          break;
        case 'prepend':
          element.insertBefore(jsonToDOM(ws, change.value), element.firstChild);
          break;
        case 'delete':
          element.remove();
          break;
        case 'updateproperties':
          updateElementProperties(element, change.properties);
          break;
        case 'updatetext':
          element.textContent = change.value;
          break;
        case 'updateevents':
          updateElementEvents(element, change.remove, change.value);
          break;
        default:
          console.error('Unknown diff action:', change.action);
      }
    } else {
      console.error('Element not found for selector:', change.selector);
    }
  }
}

function updateElementProperties(element, properties) {
  for (const attr of element.getAttributeNames()) {
    if (!isProtectedAttribute(attr)) {
      element.removeAttribute(attr);
    }
  }
  for (const [key, value] of Object.entries(properties)) {
    if (!isProtectedAttribute(key)) {
      element.setAttribute(key, value);
    }
    if (key === "value") {
      element.value = value;
    }
  }
}

function updateElementEvents(element, removeEvents, addEvents) {
  for (const eventName of removeEvents) {
    if (LISTENERS[element.id] && LISTENERS[element.id][eventName]) {
      console.log('removing event listener for', eventName, 'on', element);
      element.removeEventListener(eventName, LISTENERS[element.id][eventName]);
    }
    element.removeAttribute('data-zen-listener-' + eventName + '-set');
  }
  element.setAttribute('data-zen-event', addEvents.join(","));
}

function payloadForEvent(eventName, event) {
  switch (eventName) {
    case 'click':
      return {
        x: event.clientX,
        y: event.clientY
      };
    case 'mouseover':
      return {
        x: event.clientX,
        y: event.clientY
      };
    case 'input':
      return event.target.value;
    default:
      return {};
  }
}

function stringToIntList(str) {
  return str ? str.split('-').map(num => parseInt(num, 10)) : [];
}

function idToPath(id) {
  if (id === 'root') {
    return [];
  } else {
    return stringToIntList(id);
  }
}

function pathToHandler(path) {
  if (path.length == 0) {
    return "root"
  }
  return path
}

function jsonToDOM(ws, node) {
  if (node.tag === undefined) {
    // Handle text nodes separately
    const textNode = document.createTextNode(node.text || "");
    ZEN_NODES[node.id] = textNode;
    return textNode;
  }

  const element = document.createElement(node.tag);
  const id = node.id;

  if (node.attributes) {
    for (const [key, value] of Object.entries(node.attributes)) {
      element.setAttribute(key, value);
      if (key === "value") {
        element.value = value;
      }
    }
  }

  if (node.events) {
    for (const eventName of node.events) {
      element.addEventListener(eventName, (event) => {
        ws.send(JSON.stringify({
          handler: id,
          name: eventName,
          payload: payloadForEvent(eventName, event)
        }));
      });
    }
  }

  if (node.children) {
    for (const child of node.children) {
      element.appendChild(jsonToDOM(ws, child));
    }
  }

  if (node.text) {
      element.textContent = node.text;
  }

  ZEN_NODES[node.id] = element;
  return element;
}


document.addEventListener('DOMContentLoaded', () => {
  ttdebugger.init(document.body.getAttribute('debug') === 'true');
  ttdebugger.addState(document.getElementById('root').innerHTML);
  ttdebugger.addMessage('init');
  const ws = openWebSocket();
  initialValuesSet();
});