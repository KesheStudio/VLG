import { invoke } from "@tauri-apps/api/core";
import { createRouter, createWebHistory, type RouteRecordRaw } from "vue-router";
import { showUnlockTip } from "@/utils/unlockTip";

const routes : RouteRecordRaw[] = [
  {
    path:"/",
    name:"home",
    component: () => import("@/views/Home.vue"),
    meta:{
      requiresUnlock : false,
    }
  }
]

const router = createRouter({
  history : createWebHistory(import.meta.env.BASE_URL),
  routes
})

let tipPending = false;

router.beforeEach(async (to) => {
  if (!to.meta.requiresUnlock) return true;
  
  if (tipPending) return false;

  let unlocked = false;

  try {
    unlocked = await invoke("isUnlock",{levelID : to.meta?.levelID})
  } catch (err){
    console.error("[router] isUnlock 失败:", err);
    return false;
  }

  if (unlocked) return true;

  tipPending = true;

  try {
    await showUnlockTip();
  } finally {
    tipPending = false;
  }

  return false;
})

// router.afterEach((to,from,failuer) => {

// })

// router.onError((err,to,from) => {

// })

export default router;