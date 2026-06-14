/**
 * SnapClick 官网交互逻辑与动效机制
 */

document.addEventListener('DOMContentLoaded', () => {
  initNavbarScroll();
  initMobileMenu();
  initScrollReveal();
  initCommandCopy();
});

/**
 * 导航栏滚动效果：向下滚动时背景变深并增加阴影
 */
function initNavbarScroll() {
  const navbar = document.getElementById('navbar');
  if (!navbar) return;

  const handleScroll = () => {
    if (window.scrollY > 50) {
      navbar.classList.add('scrolled');
    } else {
      navbar.classList.remove('scrolled');
    }
  };

  window.addEventListener('scroll', handleScroll, { passive: true });
  handleScroll(); // 初始化调用一次
}

/**
 * 移动端折叠菜单逻辑
 */
function initMobileMenu() {
  const toggleBtn = document.getElementById('nav-toggle');
  const navbar = document.getElementById('navbar');
  const mobileMenu = document.getElementById('mobile-menu');
  
  if (!toggleBtn || !mobileMenu || !navbar) return;

  const toggleMenu = () => {
    const isOpen = navbar.classList.toggle('menu-open');
    mobileMenu.classList.toggle('active', isOpen);
    
    if (isOpen) {
      document.body.style.overflow = 'hidden';
    } else {
      document.body.style.overflow = '';
    }
  };

  toggleBtn.addEventListener('click', toggleMenu);

  // 点击链接后自动收起菜单
  const mobileLinks = mobileMenu.querySelectorAll('.mobile-link');
  mobileLinks.forEach(link => {
    link.addEventListener('click', () => {
      navbar.classList.remove('menu-open');
      mobileMenu.classList.remove('active');
      document.body.style.overflow = '';
    });
  });
}

/**
 * 基于 IntersectionObserver 的滚动淡入动画 (Scroll Reveal)
 */
function initScrollReveal() {
  const revealElements = document.querySelectorAll('.fade-up');
  
  if ('IntersectionObserver' in window) {
    const observerOptions = {
      root: null,
      rootMargin: '0px 0px -80px 0px', // 在距离视口底部 80px 时触发
      threshold: 0.1
    };

    const observer = new IntersectionObserver((entries, observer) => {
      entries.forEach(entry => {
        if (entry.isIntersecting) {
          entry.target.classList.add('active');
          observer.unobserve(entry.target); // 触发后即停止观察
        }
      });
    }, observerOptions);

    revealElements.forEach(el => observer.observe(el));
  } else {
    // 降级处理：若浏览器不支持 IntersectionObserver，则直接显示
    revealElements.forEach(el => el.classList.add('active'));
  }
}

/**
 * 终端命令一键复制功能
 */
function initCommandCopy() {
  const copyButtons = document.querySelectorAll('.copy-btn');
  
  copyButtons.forEach(btn => {
    btn.addEventListener('click', async () => {
      const targetId = btn.getAttribute('data-target');
      const targetElement = document.getElementById(targetId);
      if (!targetElement) return;

      const textToCopy = targetElement.textContent.trim();
      
      try {
        await navigator.clipboard.writeText(textToCopy);
        
        // 更改为复制成功状态
        const icon = btn.querySelector('i');
        if (icon) {
          icon.className = 'ph ph-check';
        }
        btn.classList.add('copied');
        
        // 2秒后恢复原样
        setTimeout(() => {
          if (icon) {
            icon.className = 'ph ph-copy';
          }
          btn.classList.remove('copied');
        }, 2000);
        
      } catch (err) {
        console.error('复制失败: ', err);
      }
    });
  });
}
