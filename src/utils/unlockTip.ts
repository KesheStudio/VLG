import { createVNode, render } from "vue";
import UnlockTip from "@/components/UnlockTip.vue";

export function showUnlockTip(): Promise<void> {
  return new Promise((resolve) => {
    const container = document.createElement("div");
    document.body.appendChild(container);

    const cleanup = () => {
      render(null, container);
      container.remove();
      resolve();
    };

    render(createVNode(UnlockTip, { onOk: cleanup }), container);
  });
}