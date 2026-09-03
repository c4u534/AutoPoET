document.addEventListener('DOMContentLoaded', () => {
    console.log("AutoPoET UI Initialized.");

    const runBtn = document.getElementById('run-sim-btn');
    const jsonOutput = document.getElementById('json-output');
    const outputContainer = document.getElementById('output-container');

    runBtn.addEventListener('click', async () => {
        runBtn.disabled = true;
        runBtn.textContent = 'Executing...';
        jsonOutput.textContent = 'Contacting Framework...';

        try {
            const response = await fetch('/api/execute');
            if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`);

            const data = await response.json();

            outputContainer.querySelector('p').textContent = 'Execution Result:';
            jsonOutput.textContent = JSON.stringify(data, null, 2);

        } catch(e) {
            console.error("Execution failed", e);
            jsonOutput.textContent = `Execution Failed: ${e.message}`;
        } finally {
            runBtn.disabled = false;
            runBtn.textContent = 'Run Intelligence Simulation';
        }
    });
});
