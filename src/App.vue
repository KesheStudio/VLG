<script lang="ts" setup>
import { onMounted, ref, nextTick } from "vue";
import { RouterView } from "vue-router";
import { initConfig } from "@/types/config/init";
import { FileAPI } from "@/utils/FileAPI";
import { useKVStore } from "@/stores/kv";
import { playFadeInOut } from "@/utils/animations";

const loadingImageUrl = ref<string>("");
const vlgLogoRef = ref<HTMLImageElement>();
const loadingRef = ref<HTMLImageElement>();
const isImageReady = ref<boolean>(false);
const showRouter = ref<boolean>(false);
const kv = useKVStore();

const playAnimationSequence = async () => {
  await nextTick();

  if (vlgLogoRef.value) {
    await playFadeInOut(vlgLogoRef.value, {
      duration: 2500,
      keyframes: [
        { opacity: 0 },
        { opacity: 1, offset: 0.3333 },
        { opacity: 1, offset: 0.6666 },
        { opacity: 0 },
      ],
    });
  }

  if (loadingRef.value) {
    await playFadeInOut(loadingRef.value, {
      duration: 2500,
    });
  }

  showRouter.value = true;
};

const init = async (): Promise<void> => {
  try {
    const initConfig = await FileAPI.readConfig<initConfig>("config/mainPage.json");
    const loadingUrl = (await FileAPI.readAsBlobUrl(initConfig.loadingImage)).url;
    const mainUrl = (await FileAPI.readAsBlobUrl(initConfig.backgroundImage)).url;

    loadingImageUrl.value = loadingUrl;
    kv.set("mainBackgroundImageUrl", mainUrl);
    isImageReady.value = true;

    playAnimationSequence();
  } catch (e) {
    console.error("初始化失败:", e);
  }
};

onMounted(() => {
  init();
});
</script>

<template>
  <div class="TopBox">
    <div v-if="!isImageReady" class="placeholder">资源加载中请等待...</div>
    <template v-else>
      <img
        ref="vlgLogoRef"
        src="/vlgLoading.jpg"
        class="vlg-logo"
        alt="VLG Logo"
      />
      <img
        ref="loadingRef"
        :src="loadingImageUrl"
        alt="logo"
        class="logo-img"
      />
    </template>
    <RouterView v-if="showRouter" class="main" />
  </div>
</template>

<style lang="scss" scoped>
.TopBox {
  aspect-ratio: 16 / 9;
  width: 100vw;
  max-height: 100vh;
  max-width: calc(100vh * 16 / 9);
  background-color: #000000;
  position: relative;
  overflow: hidden;

  & > * {
    width: 100%;
    height: 100%;
    object-fit: cover;
    display: block;
  }

  .vlg-logo {
    position: absolute;
    top: 0;
    left: 0;
    z-index: 2;
    opacity: 0;
  }

  .logo-img {
    position: absolute;
    top: 0;
    left: 0;
    z-index: 1;
    opacity: 0;
  }

  .main {
    position: absolute;
    top: 0;
    left: 0;
    z-index: 0;
  }
}
</style>