// NAVBAR SCROLL EFFECT
window.addEventListener('scroll', () => {
    const navbar = document.querySelector('.navbar');
    if (window.scrollY > 50) {
        navbar.classList.add('scrolled');
    } else {
        navbar.classList.remove('scrolled');
    }
});

// INTERACTIVE TAB SYSTEM
window.switchTab = function(tabName) {
    // Deactivate all tabs
    document.querySelectorAll('.tab-btn').forEach(btn => btn.classList.remove('active'));
    document.querySelectorAll('.tab-content').forEach(content => content.classList.remove('active'));

    // Activate the clicked tab
    const selectedBtn = Array.from(document.querySelectorAll('.tab-btn')).find(btn => btn.getAttribute('onclick').includes(tabName));
    if (selectedBtn) selectedBtn.classList.add('active');

    const selectedContent = document.getElementById(`tab-${tabName}`);
    if (selectedContent) selectedContent.classList.add('active');
}

// EARNINGS CALCULATOR
const hoursSlider = document.getElementById('hours-slider');
const hoursDisplay = document.getElementById('hours-display');
const earningsValue = document.getElementById('earnings-value');

if (hoursSlider) {
    hoursSlider.addEventListener('input', (e) => {
        const hours = parseInt(e.target.value);
        hoursDisplay.textContent = `${hours}h`;
        
        // Calculation: R$ 25 per hour * hours per day * 6 days a week
        const dailyRate = 25;
        const daysPerWeek = 6;
        const totalEarnings = hours * dailyRate * daysPerWeek;
        
        // Format as Brazilian Real currency
        const formattedEarnings = new Intl.NumberFormat('pt-BR', {
            style: 'currency',
            currency: 'BRL'
        }).format(totalEarnings);
        
        earningsValue.textContent = formattedEarnings;
    });
}
