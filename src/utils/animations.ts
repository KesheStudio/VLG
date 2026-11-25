export interface FadeInOutOptions {
  duration?: number;
  easing?: string;
  fill?: FillMode;
  autoHide?: boolean;
  keyframes?: Keyframe[];
}

/**
 * 通用渐入 停顿  淡出动画
 * @param element 目标 DOM 元素
 * @param options 动画配置
 * @returns Promise，动画完成后 resolve
 */
export function playFadeInOut(
  element: HTMLElement,
  options: FadeInOutOptions = {}
): Promise<void> {
  const {
    duration = 3000,
    easing = 'ease-in-out',
    fill = 'forwards',
    autoHide = true,
    keyframes = [
      { opacity: 0 },
      { opacity: 1, offset: 0.3333 },
      { opacity: 1, offset: 0.6666 },
      autoHide ? { opacity: 0 } : {opacity: 1}
    ],
  } = options;

  const animation = element.animate(keyframes, {
    duration,
    easing,
    fill,
  });

  return animation.finished.then(() => {
    if (autoHide) {
      element.style.display = 'none';
    }
  });
}