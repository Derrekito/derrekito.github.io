// Add collapse toggle to code blocks
document.addEventListener('DOMContentLoaded', function() {
  document.querySelectorAll('.code-header').forEach(function(header) {
    // Create collapse button
    const collapseBtn = document.createElement('button');
    collapseBtn.className = 'code-collapse-btn';
    collapseBtn.innerHTML = '<i class="fas fa-chevron-down"></i>';
    collapseBtn.title = 'Collapse code';
    collapseBtn.setAttribute('aria-label', 'Collapse code block');

    // Insert at the beginning of the header
    header.insertBefore(collapseBtn, header.firstChild);

    // Find the code content
    const wrapper = header.closest('div.highlighter-rouge');
    const codeContent = wrapper.querySelector('.highlight, pre');

    // Toggle collapse on click
    collapseBtn.addEventListener('click', function() {
      const isCollapsed = codeContent.classList.toggle('collapsed');
      collapseBtn.innerHTML = isCollapsed
        ? '<i class="fas fa-chevron-right"></i>'
        : '<i class="fas fa-chevron-down"></i>';
      collapseBtn.title = isCollapsed ? 'Expand code' : 'Collapse code';
    });
  });
});
