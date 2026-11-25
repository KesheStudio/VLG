<script lang="ts" setup>
import { computed, onMounted, ref } from "vue";
import { storeToRefs } from "pinia";
import { useKVStore } from "@/stores/kv";
import { playFadeInOut } from "@/utils/animations";
import { AudioPlayer } from "@/utils/audioPlayer";
import { type Settings } from "@/types/config/settings";
import { type initConfig } from "@/types/config/init";

import { FileAPI } from "@/utils/FileAPI";

const kv = useKVStore();
const { map } = storeToRefs(kv);
const backgroundImageRef = ref<HTMLImageElement>();

const init = async (): Promise<void> => {
  if (!backgroundImageRef.value) return;
    const settings = await FileAPI.readConfig<Settings>("config/settings.json");
  const initConfig = await FileAPI.readConfig<initConfig>(
    "config/mainPage.json",
  );

  if (settings?.audio?.music?.isPlay) {
    if (settings.audio.music.isFadePlay) {
      AudioPlayer.bgm.fadePlay(
        initConfig.backgroundMusic,
        settings.audio.music.fadeTime ?? 1000,
        { startingVolume: 0, targetVolume: settings.audio.music.volume ?? 1 },
      );
    } else {
      AudioPlayer.bgm.play(initConfig.backgroundMusic);
    }
  }
  await playFadeInOut(backgroundImageRef.value, {
    duration: 1500,
    autoHide: false,
  });

};

const backgroundImage = computed(
  () => map.value["mainBackgroundImageUrl"] as string | undefined,
);

onMounted(() => {
  init();
});
</script>

<template>
  <div class="TContent">
    <img
      v-if="backgroundImage"
      ref="backgroundImageRef"
      :src="backgroundImage"
      alt="background"
      class="background"
    />
  </div>
</template>
<style lang="scss" scoped>
.background{
  opacity: 0;
}

</style>