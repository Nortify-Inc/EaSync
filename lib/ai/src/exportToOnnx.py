from __future__ import annotations

import argparse
import enum
import sys
import time
from pathlib import Path
from typing import Any, Tuple

import torch

try:
	from .model import AgentLM
except ImportError:
	from model import AgentLM


class AgentLMLogitsWrapper(torch.nn.Module):
	def __init__(self, model: AgentLM) -> None:
		super().__init__()
		self.model = model

	def forward(self, token_ids: torch.Tensor) -> torch.Tensor:
		return self.model.forward(token_ids)["logits"]


class HFCausalLMLogitsWrapper(torch.nn.Module):
	def __init__(self, model: Any) -> None:
		super().__init__()
		self.model = model

	def forward(self, input_ids: torch.Tensor, attention_mask: torch.Tensor) -> torch.Tensor:
		out = self.model(
			input_ids=input_ids,
			attention_mask=attention_mask,
			use_cache=False,
			return_dict=True,
		)
		return out.logits


def _resolve_dtype(dtype_name: str) -> torch.dtype:
	mapping = {
		"float32": torch.float32,
		"float16": torch.float16,
		"bfloat16": torch.bfloat16,
	}
	if dtype_name not in mapping:
		raise ValueError(f"Unsupported dtype: {dtype_name}")
	return mapping[dtype_name]


def _build_dummy_inputs(seq_len: int, device: torch.device) -> torch.Tensor:
	# 1 is <|im_start|> in the tokenizer used by this project.
	token_ids = torch.full((1, seq_len), 1, dtype=torch.long, device=device)
	return token_ids


def _build_hf_dummy_inputs(seq_len: int, device: torch.device, pad_token_id: int) -> Tuple[torch.Tensor, torch.Tensor]:
	input_ids = torch.full((1, seq_len), int(pad_token_id), dtype=torch.long, device=device)
	attention_mask = torch.ones_like(input_ids, dtype=torch.long)
	return input_ids, attention_mask


def _install_torchvision_stub() -> None:
	import types

	tv = types.ModuleType("torchvision")
	tv.__dict__["__all__"] = ["transforms"]

	transforms = types.ModuleType("torchvision.transforms")

	class InterpolationMode(enum.Enum):
		NEAREST = 0
		BILINEAR = 2
		BICUBIC = 3
		BOX = 4
		HAMMING = 5
		LANCZOS = 1

	transforms.InterpolationMode = InterpolationMode
	tv.transforms = transforms

	sys.modules["torchvision"] = tv
	sys.modules["torchvision.transforms"] = transforms


def _import_hf_auto_classes() -> Tuple[Any, Any]:
	_install_torchvision_stub()
	try:
		from transformers import AutoModelForCausalLM, AutoTokenizer
		return AutoModelForCausalLM, AutoTokenizer
	except Exception:
		from transformers import AutoModelForCausalLM, AutoTokenizer
		return AutoModelForCausalLM, AutoTokenizer


def _export_native(
	model_ref: str,
	output_path: Path,
	opset: int,
	seq_len: int,
	dtype_name: str,
	device_name: str,
	validate: bool,
) -> None:
	device = torch.device(device_name)
	dtype = _resolve_dtype(dtype_name)

	model_path = Path(model_ref)
	if not model_path.exists():
		raise FileNotFoundError(f"Model directory not found: {model_path}")

	model = AgentLM.load(model_path, device=device_name, dtype=dtype)
	wrapped = AgentLMLogitsWrapper(model)
	wrapped.eval()

	token_ids = _build_dummy_inputs(seq_len=seq_len, device=device)

	torch.onnx.export(
		wrapped,
		(token_ids,),
		str(output_path),
		export_params=True,
		opset_version=opset,
		do_constant_folding=True,
		input_names=["token_ids"],
		output_names=["logits"],
		dynamic_axes={
			"token_ids": {0: "batch", 1: "sequence"},
			"logits": {0: "batch", 1: "sequence"},
		},
	)

	if validate:
		import onnx
		onnx.checker.check_model(onnx.load(str(output_path)))


def _export_hf(
	model_ref: str,
	output_path: Path,
	opset: int,
	seq_len: int,
	dtype_name: str,
	device_name: str,
	validate: bool,
) -> None:
	device = torch.device(device_name)
	dtype = _resolve_dtype(dtype_name)
	if device.type == "cpu" and dtype == torch.float16:
		raise ValueError("float16 on CPU is not supported. Use float32 or bfloat16.")

	AutoModelForCausalLM, AutoTokenizer = _import_hf_auto_classes()

	ref_path = Path(model_ref)
	local_only = ref_path.exists()
	tokenizer = AutoTokenizer.from_pretrained(model_ref, local_files_only=local_only)
	model = AutoModelForCausalLM.from_pretrained(model_ref, local_files_only=local_only)
	model.eval()
	model.to(device)
	model.to(dtype=dtype)

	pad_token_id = tokenizer.pad_token_id
	if pad_token_id is None:
		pad_token_id = tokenizer.eos_token_id if tokenizer.eos_token_id is not None else 2

	input_ids, attention_mask = _build_hf_dummy_inputs(seq_len=seq_len, device=device, pad_token_id=int(pad_token_id))
	wrapped = HFCausalLMLogitsWrapper(model)

	torch.onnx.export(
		wrapped,
		(input_ids, attention_mask),
		str(output_path),
		export_params=True,
		opset_version=opset,
		do_constant_folding=True,
		input_names=["input_ids", "attention_mask"],
		output_names=["logits"],
		dynamic_axes={
			"input_ids": {0: "batch", 1: "sequence"},
			"attention_mask": {0: "batch", 1: "sequence"},
			"logits": {0: "batch", 1: "sequence"},
		},
	)

	if validate:
		import onnx
		onnx.checker.check_model(onnx.load(str(output_path)))


def export_onnx(
	model_ref: str,
	output_path: Path,
	opset: int,
	seq_len: int,
	dtype_name: str,
	device_name: str,
	backend: str,
	validate: bool,
) -> None:
	start = time.time()

	output_path.parent.mkdir(parents=True, exist_ok=True)

	selected = backend.lower().strip()
	if selected == "auto":
		selected = "hf"

	if selected == "hf":
		_export_hf(model_ref, output_path, opset, seq_len, dtype_name, device_name, validate)
	elif selected == "native":
		_export_native(model_ref, output_path, opset, seq_len, dtype_name, device_name, validate)
	else:
		raise ValueError(f"Unsupported backend: {backend}")

	duration = time.time() - start
	size_mb = output_path.stat().st_size / (1024 * 1024)
	print(f"ONNX export completed: {output_path}")
	print(f"Size: {size_mb:.2f} MB")
	print(f"Elapsed: {duration:.1f} s")


def parse_args() -> argparse.Namespace:
	default_model_dir = Path(__file__).resolve().parent.parent / "data"
	default_output = default_model_dir / "model.onnx"

	parser = argparse.ArgumentParser(description="Export a causal LM checkpoint to ONNX")
	parser.add_argument(
		"--model-ref",
		type=str,
		default=str(default_model_dir),
		help="Local model directory or Hugging Face model id",
	)
	parser.add_argument(
		"--output",
		type=str,
		default=str(default_output),
		help="Output ONNX file path",
	)
	parser.add_argument("--opset", type=int, default=17, help="ONNX opset version")
	parser.add_argument("--seq-len", type=int, default=32, help="Dummy sequence length for tracing")
	parser.add_argument("--dtype", choices=["float32", "float16", "bfloat16"], default="float32")
	parser.add_argument("--device", choices=["cpu", "cuda"], default="cpu")
	parser.add_argument("--backend", choices=["auto", "hf", "native"], default="auto")
	parser.add_argument("--no-validate", action="store_true", help="Skip ONNX checker validation")
	return parser.parse_args()


def main() -> None:
	args = parse_args()
	output_path = Path(args.output).resolve()

	export_onnx(
		model_ref=args.model_ref,
		output_path=output_path,
		opset=args.opset,
		seq_len=args.seq_len,
		dtype_name=args.dtype,
		device_name=args.device,
		backend=args.backend,
		validate=not args.no_validate,
	)


if __name__ == "__main__":
	main()

