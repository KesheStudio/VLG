<script lang="ts" setup>
import { onMounted, ref, nextTick } from "vue";
import { RouterView } from "vue-router";
import type { InitConfig } from "@/types/config/init";
import { FileAPI } from "@/utils/fileAPI";
import { useKVStore } from "@/stores/kv";
import { playFadeInOut } from "@/utils/animations";
import { AudioPlayer } from "./utils/audioPlayer";

const loadingImageUrl = ref<string>("");
const vlgLogoRef = ref<HTMLImageElement>();
const loadingRef = ref<HTMLImageElement>();
const isImageReady = ref<boolean>(false);
const showRouter = ref<boolean>(false);
const kv = useKVStore();
let initConfig: object | InitConfig = {};

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
    initConfig = await FileAPI.readConfig<InitConfig>("config/mainPage.json");

    const loadingUrl = (
      await FileAPI.readAsBlobUrl((initConfig as InitConfig).loadingImage)
    ).url;

    loadingImageUrl.value = loadingUrl;
    isImageReady.value = true;

    playAnimationSequence();
  } catch (e) {
    console.error("初始化失败:", e);
  }
};

const loadRes = async (): Promise<void> => {
  AudioPlayer.bgm.queue.addMany(["audio/res.ogg"])
  AudioPlayer.bgm.queue.loadAll()
  kv.set(
    "mainBackgroundImageUrl",
    (await FileAPI.readAsBlobUrl((initConfig as InitConfig).backgroundImage))
      .url,
  );
  kv.set(
    "playGameImage",
    (await FileAPI.readAsBlobUrl("image/ui/button/playGame.png")).url,
  );
  kv.set(
    "loadSaveImage",
    (await FileAPI.readAsBlobUrl("image/ui/button/loadSave.png")).url,
  );
  kv.set(
    "unlockedResourcesImage",
    (await FileAPI.readAsBlobUrl("image/ui/button/unlockedResources.png")).url,
  );
  kv.set(
    "gameSettingsImage",
    (await FileAPI.readAsBlobUrl("image/ui/button/gameSettings.png")).url,
  );
  kv.set(
    "sideStoryImage",
    (await FileAPI.readAsBlobUrl("image/ui/button/sideStory.png")).url,
  );
  kv.set(
    "exitGameImage",
    (await FileAPI.readAsBlobUrl("image/ui/button/exitGame.png")).url,
  );
};

onMounted(async() => {

  await init();
  loadRes();
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
.placeholder {
  color: #ffffff;
  // font-size: ;
  display: flex;
  justify-content: center;
  align-items: center;
  text-align: center;
}
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

<style>
* {
  margin: 0;
  padding: 0;
  box-sizing: border-box;
  user-select: none;
  -webkit-user-select: none;
  -webkit-user-drag: none !important;
  -webkit-touch-callout: none;
  -ms-user-select: none;
  -moz-user-select: none;
}

#app {
  margin: 0;
  display: flex;
  justify-content: center;
  align-items: center;
  height: 100vh;
  background: #111;
}

img,
video,
audio,
canvas,
svg {
  user-select: none !important;
  -webkit-user-select: none !important;
  pointer-events: auto;
}

a {
  -webkit-user-drag: none !important;
}

img,
video,
audio {
  -webkit-user-drag: none !important;
}
</style>
