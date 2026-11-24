<script lang="ts" setup>
import { onMounted, ref } from "vue";

const emit = defineEmits<{ (e: "ok"): void }>();
const btnRef = ref<HTMLButtonElement>();

onMounted(() => btnRef.value?.focus());

const onOk = () => emit("ok");
</script>
<template>
  <div class="tip-mask" @click.self="onOk" @keydown.enter="onOk">
    <div class="tip-dialog">
      <p class="tip-text">当前章节尚未解锁</p>
      <button class="tip-btn" @click="onOk" ref="btnRef">确定</button>
    </div>
  </div>
</template>

<style scoped>
.tip-mask {
  position: fixed;
  inset: 0;
  background: rgba(0, 0, 0, 0.5);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 9999;
}
.tip-dialog {
  background: #1e1e2e;
  color: #eee;
  border-radius: 10px;
  padding: 28px 36px;
  min-width: 280px;
  text-align: center;
  box-shadow: 0 8px 32px rgba(0, 0, 0, 0.4);
}
.tip-text {
  margin: 0 0 20px;
  font-size: 16px;
}
.tip-btn {
  padding: 8px 28px;
  border: none;
  border-radius: 6px;
  background: #6c5ce7;
  color: #fff;
  font-size: 14px;
  cursor: pointer;
}
.tip-btn:hover {
  background: #5a4bd1;
}
</style>
