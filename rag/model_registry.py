import logging
import os
import shutil
import sys
from collections import OrderedDict

from sentence_transformers import SentenceTransformer

logger = logging.getLogger(__name__)


def _ensure_jina_flash_code_in_hf_cache():
    ms_src = os.path.expanduser(
        "~/.cache/modelscope/hub/models/jinaai/xlm-roberta-flash-implementation"
    )
    hf_dst = os.path.expanduser(
        "~/.cache/huggingface/modules/transformers_modules"
        "/jinaai/xlm-roberta-flash-implementation"
    )
    if not os.path.exists(ms_src):
        try:
            import modelscope
            modelscope.snapshot_download("jinaai/xlm-roberta-flash-implementation")
        except Exception:
            pass
    if not os.path.exists(ms_src):
        logger.warning("ModelScope上未找到jinaai/xlm-roberta-flash-implementation")
        return
    os.makedirs(hf_dst, exist_ok=True)
    for f in os.listdir(ms_src):
        if f.startswith(".") or f in ("README.md", "configuration.json"):
            continue
        src_path = os.path.join(ms_src, f)
        dst_path = os.path.join(hf_dst, f)
        if os.path.isfile(src_path) and not os.path.exists(dst_path):
            shutil.copy2(src_path, dst_path)
    init_path = os.path.join(hf_dst, "__init__.py")
    if not os.path.exists(init_path):
        with open(init_path, "w") as fh:
            fh.write("")


def _monkey_patch_all_tied_weights_keys():
    try:
        from transformers import modeling_utils
        original = modeling_utils.PreTrainedModel._adjust_tied_keys_with_tied_pointers

        def patched(self, loading_info):
            if not hasattr(self, "all_tied_weights_keys"):
                self.all_tied_weights_keys = {}
            return original(self, loading_info)

        modeling_utils.PreTrainedModel._adjust_tied_keys_with_tied_pointers = patched
        logger.debug("已monkey-patch _adjust_tied_keys_with_tied_pointers")
    except Exception as e:
        logger.debug(f"monkey-patch跳过: {e}")


class ModelRegistry:
    MODELSCOPE_MAP: dict = {
        "BAAI/bge-large-zh-v1.5": "AI-ModelScope/bge-large-zh-v1.5",
        "jina-code-embeddings-0.5b": "jinaai/jina-code-embeddings-0.5b",
    }
    MODEL_DIM_MAP: dict = {
        "BAAI/bge-large-zh-v1.5": 1024,
        "jina-code-embeddings-0.5b": 896,
    }
    MODEL_TRUST_REMOTE_CODE: set = set()
    MODEL_PROMPT_MAP: dict = {
        "BAAI/bge-large-zh-v1.5": {
            "query": "query",
            "passage": "document",
        },
        "jina-code-embeddings-0.5b": {
            "query": "nl2code_query",
            "passage": "nl2code_document",
        },
    }
    _model_cache: OrderedDict = OrderedDict()
    _max_cached_models: int = 1
    _flash_code_ready: bool = False

    @classmethod
    def set_max_cached_models(cls, n: int):
        cls._max_cached_models = max(1, n)

    @classmethod
    def get_model(cls, model_name: str) -> SentenceTransformer:
        if model_name in cls._model_cache:
            cls._model_cache.move_to_end(model_name)
            return cls._model_cache[model_name]
        if model_name not in cls.MODELSCOPE_MAP:
            raise ValueError(f"未知模型: {model_name}, 可用: {cls.available_models()}")

        while len(cls._model_cache) >= cls._max_cached_models:
            evicted_name, evicted_model = cls._model_cache.popitem(last=False)
            del evicted_model
            import gc
            gc.collect()
            logger.info(f"LRU淘汰模型: {evicted_name}")

        modelscope_id = cls.MODELSCOPE_MAP[model_name]
        try:
            import modelscope
            logger.info(f"从魔搭(ModelScope)下载模型: {modelscope_id}")
            cache_dir = modelscope.snapshot_download(modelscope_id)
            logger.info(f"下载完成 → {cache_dir}")
        except ImportError:
            logger.error("请先安装依赖: pip install modelscope")
            sys.exit(1)
        except Exception as e:
            logger.error(f"模型下载失败: {modelscope_id}, 错误: {e}")
            raise
        try:
            trust = model_name in cls.MODEL_TRUST_REMOTE_CODE
            model = SentenceTransformer(cache_dir, trust_remote_code=trust)
            cls._model_cache[model_name] = model
            logger.info(f"模型加载成功: {model_name} (缓存数={len(cls._model_cache)}/{cls._max_cached_models})")
            return model
        except Exception as e:
            logger.error(f"模型加载失败: {model_name}, 错误: {e}")
            raise

    @classmethod
    def encode(cls, model_name: str, texts: list[str], prompt_name: str = "") -> list[list[float]]:
        model = cls.get_model(model_name)
        actual_prompt = ""
        if prompt_name:
            prompt_map = cls.MODEL_PROMPT_MAP.get(model_name, {})
            actual_prompt = prompt_map.get(prompt_name, prompt_name)
        if actual_prompt:
            embeddings = model.encode(texts, prompt_name=actual_prompt, normalize_embeddings=True, show_progress_bar=False)
        else:
            embeddings = model.encode(texts, normalize_embeddings=True, show_progress_bar=False)
        return embeddings

    @classmethod
    def get_dim(cls, model_name: str) -> int:
        if model_name in cls.MODEL_DIM_MAP:
            return cls.MODEL_DIM_MAP[model_name]
        raise ValueError(f"未知模型维度: {model_name}, 可用: {cls.available_models()}")

    @classmethod
    def available_models(cls) -> list:
        return list(cls.MODELSCOPE_MAP.keys())

    @classmethod
    def validate_model(cls, model_name: str) -> bool:
        model = cls.get_model(model_name)
        expected_dim = cls.get_dim(model_name)
        test_embedding = model.encode(["test query"])
        actual_dim = test_embedding.shape[1]
        if actual_dim != expected_dim:
            logger.warning(f"模型 {model_name} 输出维度 {actual_dim} 与预期 {expected_dim} 不一致")
            return False
        return True
