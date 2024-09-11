const LISTENERS = {}
const LOCK = false

function openWebSocket() {
  const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
  const host = window.location.host;
  const ws = new WebSocket(`${protocol}//${host}/ws`);
  const HEARTBEAT_INTERVAL = 10000;

  ws.onopen = () => {
    console.log('WebSocket connection established');
    ws.send("ping");
    // Schedule heartbeat every second
    setInterval(() => {
      if (ws.readyState === WebSocket.OPEN) {
        ws.send("ping");
      }
    }, HEARTBEAT_INTERVAL);
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
  if (message.title !== undefined) {
    document.title = message.title
  }
  if (message.body) {
    document.body.innerHTML = message.body;
  } else if (message.diff) {
    applyDiff(message.diff);
  } else {
    console.error('Invalid message format: neither body nor diff found');
  }
}

function isProtectedAttribute(attr) {
  return attr == "id" || attr.slice(0, 10) == "data-event"
}

function applyDiff(diff) {
  for (const change of diff) {
    const element = findNodeByIntList(change.selector);
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
          for (const attr in element.getAttributeNames()) {
            // id is a protected category
            if (!isProtectedAttribute(attr)) {
              element.removeAttribute(attr)
            }
          }
          for (const [key, value] of Object.entries(change.properties)) {
            if (!isProtectedAttribute(attr)) {
              element.setAttribute(key, value)
            }
          }
          break;
        case 'updatetext':
          element.textContent = change.value;
          break;
        case 'updateevents':
          for (const eventName of change.remove) {
            if (LISTENERS[element.id] && LISTENERS[element.id][eventName]) {
              console.log('removing event listener for', eventName, 'on', element)
              element.removeEventListener(eventName, LISTENERS[element.id][eventName])
            }
            element.removeAttribute('data-listener-' + eventName + '-set')
          }
          element.setAttribute('data-event', change.value.join(","))
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

function findNodeByIntList(intList) {
  let node = document.getElementById('root'); // Start at the root
  if (intList == "root") {
    return node
  }

  const reversedList = [...intList].reverse();
  
  for (const index of reversedList) {
    if (node.childNodes.length > index) {
      console.log("node", node, "index", index, "child", node.childNodes[index])
      node = node.childNodes[index];
    } else {
      console.error('Invalid path: child index out of bounds', index);
      return null;
    }
  }
  
  return node;
}

function pathToHandler(path) {
  if (path.length == 0) {
    return "root"
  }
  return path
}

function setEventListeners(ws) {
  const targets = document.querySelectorAll('[data-event]');
  for (const target of targets) {
    const eventNames = target.getAttribute('data-event').split(",");
    const id = target.getAttribute('id');
    const path = idToPath(id);
    const handler = pathToHandler(path);
    
    // Check if the event listener is already set
    for (const eventName of eventNames) {
      if (eventName !== "" && !target.hasAttribute('data-listener-' + eventName + '-set')) {
        const eventHandler = (event) => {
          ws.send(JSON.stringify({
            handler: handler,
            name: eventName,
            payload: payloadForEvent(eventName, event)
          }));
        };
        if (!LISTENERS[id]) {
          LISTENERS[id] = {}
        }
        LISTENERS[id][eventName] = eventHandler
        target.addEventListener(eventName, eventHandler);
        
        // Mark this element as having a listener set
        target.setAttribute('data-listener-' + eventName + '-set', 'true');
      }
    }
  }
}

document.addEventListener('DOMContentLoaded', () => {
  const ws = openWebSocket();
  setEventListeners(ws);
});