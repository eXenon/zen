function timeTravelDebugger() {
    let states = [];
    let messages = [];
    let currentIndex = 0;
    let enabled = false;

    function init(debug) {
        enabled = debug;
        if (!enabled) {
            return;
        }
        const debuggerDiv = document.createElement('div');
        debuggerDiv.id = 'debugger';
        debuggerDiv.style.cssText = `
            position: fixed;
            bottom: 20px;
            right: 20px;
            width: 500px;
            height: 300px;
            background-color: rgba(0, 0, 0, 0.8);
            color: white;
            padding: 10px;
            font-family: monospace;
            overflow-y: auto;
            z-index: 9999;
        `;

        const slider = document.createElement('input');
        slider.type = 'range';
        slider.min = '0';
        slider.max = '0';
        slider.value = '0';
        slider.style.width = '100%';
        slider.addEventListener('input', updateDisplay);

        const content = document.createElement('div');
        content.id = 'debugger-content';

        debuggerDiv.appendChild(slider);
        debuggerDiv.appendChild(content);
        document.body.appendChild(debuggerDiv);
    }

    function addState(state) {
        if (!enabled) {
            return;
        }
        states.push(state);
        updateSlider();
    }

    function addMessage(message) {
        if (!enabled) {
            return;
        }
        messages.push(message);
        updateSlider();
    }

    function updateSlider() {
        if (!enabled) {
            return;
        }
        const slider = document.querySelector('#debugger input');
        slider.max = Math.max(states.length, messages.length) - 1;
        slider.value = slider.max;
        updateDisplay();
    }

    function updateDisplay() {
        if (!enabled) {
            return;
        }
        const content = document.getElementById('debugger-content');
        const slider = document.querySelector('#debugger input');
        currentIndex = parseInt(slider.value);

        let html = '<h3>Time: ' + currentIndex + '</h3>';

        if (states[currentIndex]) {
            html += '<h4>State:</h4>';
            html += '<button onclick="document.getElementById(\'root\').innerHTML = \'' + states[currentIndex].replaceAll("\"", "'").replaceAll("'", "\\'") + '\'">Apply State</button>';
        }

        if (messages[currentIndex]) {
            html += '<h4>Message:</h4>';
            html += '<pre>' + JSON.stringify(messages[currentIndex], null, 2) + '</pre>';
        }

        content.innerHTML = html;
    }

    return {
        init,
        addState,
        addMessage
    };
};