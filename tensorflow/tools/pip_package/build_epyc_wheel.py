#!/usr/bin/env python3
# Copyright 2024 The TensorFlow Authors. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# ==============================================================================
"""Build script for TensorFlow wheel optimized for AMD EPYC processors.

This script builds a TensorFlow Python wheel optimized for AMD EPYC processors,
specifically targeting the Zen 2 architecture (EPYC 7xx2 series like the 7702).

The script enables CPU-specific optimizations including:
- AVX2, FMA, SSE4.2, SSE4a instruction sets
- Zen 2 microarchitecture tuning (-march=znver2)
- OneDNN (MKL-DNN) optimizations for better math kernel performance
- Parallel build utilizing available CPU cores

Usage:
    python build_epyc_wheel.py [options]

Examples:
    # Basic build with default settings
    python build_epyc_wheel.py

    # Build with specific Python version
    python build_epyc_wheel.py --python=/usr/bin/python3.11

    # Build with custom output directory
    python build_epyc_wheel.py --output-dir=/tmp/wheels

    # Build with custom parallelism
    python build_epyc_wheel.py --jobs=64

    # Enable verbose output
    python build_epyc_wheel.py --verbose
"""

import argparse
import logging
import multiprocessing
import os
import platform
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import List, Optional, Tuple

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


# AMD EPYC Zen architecture mappings
# Maps CPU family and model to the appropriate -march flag
ZEN_ARCHITECTURES = {
    # Zen 1 (Naples) - EPYC 7xx1 series
    (23, 1): 'znver1',
    (23, 8): 'znver1',
    # Zen 2 (Rome) - EPYC 7xx2 series
    (23, 49): 'znver2',
    (23, 47): 'znver2',
    # Zen 3 (Milan) - EPYC 7xx3 series
    (25, 1): 'znver3',
    (25, 33): 'znver3',
    # Zen 4 (Genoa) - EPYC 9xx4 series
    (25, 17): 'znver4',
    (25, 160): 'znver4',
    (25, 161): 'znver4',
}

# Instruction set flags for AMD EPYC Zen 2 processors
ZEN2_INSTRUCTION_FLAGS = [
    '-mavx',
    '-mavx2',
    '-mfma',
    '-mf16c',
    '-msse4.1',
    '-msse4.2',
    '-msse4a',
    '-mbmi',
    '-mbmi2',
    '-maes',
    '-mpclmul',
    '-mpopcnt',
    '-mrdrnd',
    '-msha',
    '-madx',
]


class CPUInfo:
    """Detect and store CPU information for build optimization."""

    def __init__(self):
        self.vendor: str = ''
        self.family: int = 0
        self.model: int = 0
        self.model_name: str = ''
        self.cores: int = multiprocessing.cpu_count()
        self.flags: List[str] = []
        self._detect()

    def _detect(self):
        """Detect CPU information from /proc/cpuinfo."""
        if not Path('/proc/cpuinfo').exists():
            logger.warning('/proc/cpuinfo not found, using defaults')
            return

        with open('/proc/cpuinfo', 'r') as f:
            cpuinfo = f.read()

        # Parse vendor
        vendor_match = re.search(r'vendor_id\s*:\s*(\S+)', cpuinfo)
        if vendor_match:
            self.vendor = vendor_match.group(1)

        # Parse CPU family
        family_match = re.search(r'cpu family\s*:\s*(\d+)', cpuinfo)
        if family_match:
            self.family = int(family_match.group(1))

        # Parse model
        model_match = re.search(r'^model\s*:\s*(\d+)', cpuinfo, re.MULTILINE)
        if model_match:
            self.model = int(model_match.group(1))

        # Parse model name
        name_match = re.search(r'model name\s*:\s*(.+)', cpuinfo)
        if name_match:
            self.model_name = name_match.group(1).strip()

        # Parse flags
        flags_match = re.search(r'flags\s*:\s*(.+)', cpuinfo)
        if flags_match:
            self.flags = flags_match.group(1).split()

    def is_amd_epyc(self) -> bool:
        """Check if the CPU is an AMD EPYC processor."""
        return (
            self.vendor == 'AuthenticAMD' and
            'EPYC' in self.model_name
        )

    def get_zen_version(self) -> Optional[str]:
        """Get the Zen architecture version for this CPU."""
        return ZEN_ARCHITECTURES.get((self.family, self.model))

    def supports_instruction(self, instruction: str) -> bool:
        """Check if the CPU supports a specific instruction set."""
        instruction_to_flag = {
            'avx': 'avx',
            'avx2': 'avx2',
            'fma': 'fma',
            'sse4.1': 'sse4_1',
            'sse4.2': 'sse4_2',
            'sse4a': 'sse4a',
            'aes': 'aes',
            'sha': 'sha_ni',
        }
        flag = instruction_to_flag.get(instruction, instruction)
        return flag in self.flags

    def __str__(self) -> str:
        return (
            f'CPU: {self.model_name}\n'
            f'Vendor: {self.vendor}\n'
            f'Family: {self.family}, Model: {self.model}\n'
            f'Cores: {self.cores}\n'
            f'Zen Version: {self.get_zen_version() or "Unknown"}'
        )


class TensorFlowWheelBuilder:
    """Build TensorFlow wheels optimized for AMD EPYC processors."""

    def __init__(
        self,
        python_path: Optional[str] = None,
        output_dir: Optional[str] = None,
        jobs: Optional[int] = None,
        verbose: bool = False,
        enable_onednn: bool = True,
        enable_xla: bool = True,
        wheel_name: str = 'tensorflow',
        target_platform: str = 'manylinux2014',
    ):
        self.cpu_info = CPUInfo()
        self.python_path = python_path or sys.executable
        self.output_dir = Path(output_dir) if output_dir else Path.cwd() / 'wheel_output'
        self.jobs = jobs or self._calculate_optimal_jobs()
        self.verbose = verbose
        self.enable_onednn = enable_onednn
        self.enable_xla = enable_xla
        self.wheel_name = wheel_name
        self.target_platform = target_platform
        self.tf_root = self._find_tensorflow_root()

    def _find_tensorflow_root(self) -> Path:
        """Find the TensorFlow source root directory."""
        # Try to find it relative to this script
        script_path = Path(__file__).resolve()

        # Navigate up to find the root (should have .bazelrc)
        current = script_path.parent
        for _ in range(10):  # Max depth
            if (current / '.bazelrc').exists():
                return current
            current = current.parent

        # Fall back to current working directory
        cwd = Path.cwd()
        if (cwd / '.bazelrc').exists():
            return cwd

        raise RuntimeError(
            'Could not find TensorFlow source root. '
            'Please run this script from the TensorFlow repository.'
        )

    def _calculate_optimal_jobs(self) -> int:
        """Calculate optimal number of parallel jobs based on CPU cores.

        For AMD EPYC with high core counts, we limit parallelism to avoid
        memory exhaustion during compilation.
        """
        cores = self.cpu_info.cores
        # Use 75% of cores, but cap at reasonable limits for memory
        # Large builds can use 10-20GB+ of RAM
        optimal = int(cores * 0.75)
        # Cap at 128 jobs to avoid memory issues
        return min(optimal, 128)

    def _get_optimization_flags(self) -> List[str]:
        """Get compiler optimization flags for AMD EPYC Zen 2."""
        flags = []

        # Determine architecture flag
        zen_version = self.cpu_info.get_zen_version()
        if zen_version:
            # Use specific Zen architecture tuning
            flags.append(f'-march={zen_version}')
            flags.append(f'-mtune={zen_version}')
            logger.info(f'Using {zen_version} architecture optimizations')
        elif self.cpu_info.is_amd_epyc():
            # Fallback for unknown EPYC models - use znver2 as safe default
            flags.append('-march=znver2')
            flags.append('-mtune=znver2')
            logger.warning(
                f'Unknown EPYC model (family={self.cpu_info.family}, '
                f'model={self.cpu_info.model}), defaulting to znver2'
            )
        else:
            # Non-EPYC AMD or other CPU - use generic x86-64-v3 for AVX2 support
            logger.warning('Non-EPYC CPU detected, using generic AVX2 flags')
            flags.extend(ZEN2_INSTRUCTION_FLAGS)

        # Optimization level
        flags.append('-O3')

        # Additional optimization flags
        flags.extend([
            '-funroll-loops',
            '-ffast-math',
            '-fno-math-errno',
        ])

        return flags

    def _get_bazel_build_flags(self) -> List[str]:
        """Get Bazel build flags for the optimized build."""
        flags = []

        # Python configuration
        python_site_packages = self._get_site_packages_path()
        flags.extend([
            f'--action_env=PYTHON_BIN_PATH={self.python_path}',
            f'--action_env=PYTHON_LIB_PATH={python_site_packages}',
        ])

        # Use release configuration for Linux
        flags.append('--config=release_cpu_linux')

        # Override AVX flags with EPYC-specific optimizations
        opt_flags = self._get_optimization_flags()
        for opt_flag in opt_flags:
            flags.append(f'--copt={opt_flag}')
            flags.append(f'--host_copt={opt_flag}')

        # Enable OneDNN for optimized math kernels
        if self.enable_onednn:
            flags.extend([
                '--define=build_with_mkl=true',
                '--define=enable_mkl=true',
                '--define=build_with_mkl_opensource=true',
                '--define=tensorflow_mkldnn_contraction_kernel=0',
            ])
            logger.info('OneDNN (MKL-DNN) optimizations enabled')

        # Enable XLA for optimized operations
        if self.enable_xla:
            flags.append('--define=with_xla_support=true')
            logger.info('XLA optimizations enabled')

        # Set wheel name
        flags.append(f'--repo_env=WHEEL_NAME={self.wheel_name}')

        # Parallelism
        flags.append(f'--jobs={self.jobs}')

        # Memory optimization for high core count systems
        flags.extend([
            '--local_ram_resources=HOST_RAM*.8',
            '--local_cpu_resources=HOST_CPUS*.75',
        ])

        # Progress reporting - always show build progress
        flags.extend([
            '--show_progress',
            '--show_progress_rate_limit=1',  # Update progress every second
            '--ui_event_filters=-info,-debug,-warning',  # Reduce noise
            '--noshow_loading_progress',  # Don't show loading messages
        ])

        # Verbose output if requested
        if self.verbose:
            flags.append('--config=verbose_logs')
            flags.append('--subcommands')  # Show actual commands being run
        else:
            flags.append('--config=short_logs')

        return flags

    def _get_site_packages_path(self) -> str:
        """Get the site-packages path for the Python interpreter."""
        result = subprocess.run(
            [self.python_path, '-c', 'import site; print(site.getsitepackages()[0])'],
            capture_output=True,
            text=True,
            check=True,
        )
        return result.stdout.strip()

    def _run_command(
        self,
        cmd: List[str],
        cwd: Optional[Path] = None,
        env: Optional[dict] = None,
        stream_output: bool = True,
    ) -> subprocess.CompletedProcess:
        """Run a command and handle errors.

        Args:
            cmd: Command and arguments to run.
            cwd: Working directory for the command.
            env: Additional environment variables.
            stream_output: If True, stream stdout/stderr to terminal in real-time.
                          If False, capture output silently.
        """
        logger.info(f'Running: {" ".join(cmd[:5])}...')
        if self.verbose:
            logger.info(f'Full command: {" ".join(cmd)}')

        merged_env = os.environ.copy()
        if env:
            merged_env.update(env)

        try:
            if stream_output:
                # Stream output to terminal in real-time for progress visibility
                result = subprocess.run(
                    cmd,
                    cwd=cwd or self.tf_root,
                    env=merged_env,
                    text=True,
                    check=True,
                )
            else:
                # Capture output silently
                result = subprocess.run(
                    cmd,
                    cwd=cwd or self.tf_root,
                    env=merged_env,
                    capture_output=True,
                    text=True,
                    check=True,
                )
            return result
        except subprocess.CalledProcessError as e:
            logger.error(f'Command failed with exit code {e.returncode}')
            if e.stdout:
                logger.error(f'stdout: {e.stdout[-2000:]}')
            if e.stderr:
                logger.error(f'stderr: {e.stderr[-2000:]}')
            raise

    def _check_prerequisites(self) -> None:
        """Check that all build prerequisites are met."""
        logger.info('Checking prerequisites...')

        # Check Python version
        py_version = sys.version_info
        if py_version < (3, 9):
            raise RuntimeError(
                f'Python 3.9+ required, found {py_version.major}.{py_version.minor}'
            )

        # Check for bazel/bazelisk
        bazel_path = shutil.which('bazel') or shutil.which('bazelisk')
        if not bazel_path:
            raise RuntimeError(
                'Bazel or Bazelisk not found in PATH. '
                'Please install Bazelisk: https://github.com/bazelbuild/bazelisk'
            )
        logger.info(f'Found bazel at: {bazel_path}')

        # Check for required Python packages
        required_packages = ['wheel', 'setuptools', 'numpy']
        for package in required_packages:
            try:
                __import__(package)
            except ImportError:
                logger.warning(f'Package {package} not found, installing...')
                subprocess.run(
                    [self.python_path, '-m', 'pip', 'install', package],
                    check=True,
                )

        # Check for patchelf (needed for wheel repair on Linux)
        if platform.system() == 'Linux':
            if not shutil.which('patchelf'):
                logger.warning('patchelf not found, wheel repair may fail')

        # Check for auditwheel (needed for manylinux compliance)
        try:
            subprocess.run(
                [self.python_path, '-m', 'auditwheel', '--version'],
                capture_output=True,
                check=True,
            )
        except (subprocess.CalledProcessError, FileNotFoundError):
            logger.warning('auditwheel not found, installing...')
            subprocess.run(
                [self.python_path, '-m', 'pip', 'install', 'auditwheel~=5.3.0'],
                check=True,
            )

        logger.info('Prerequisites check passed')

    def _setup_environment(self) -> dict:
        """Set up environment variables for the build."""
        env = {
            # Disable interactive configuration
            'TF_ENABLE_XLA': '1' if self.enable_xla else '0',
            'TF_DOWNLOAD_CLANG': '0',
            'TF_SET_ANDROID_WORKSPACE': '0',
            'TF_NEED_MPI': '0',
            'TF_NEED_ROCM': '0',
            'TF_NEED_GCP': '0',
            'TF_NEED_S3': '0',
            'TF_NEED_OPENCL_SYCL': '0',
            'TF_NEED_CUDA': '0',
            'TF_NEED_HDFS': '0',
            'TF_NEED_OPENCL': '0',
            'TF_NEED_JEMALLOC': '1',
            'TF_NEED_VERBS': '0',
            'TF_NEED_AWS': '0',
            'TF_NEED_GDR': '0',
            'TF_NEED_COMPUTECPP': '0',
            'TF_NEED_KAFKA': '0',
            'TF_NEED_TENSORRT': '0',
            # OneDNN environment
            'TF_ENABLE_ONEDNN_OPTS': '1' if self.enable_onednn else '0',
            # Python paths
            'PYTHON_BIN_PATH': self.python_path,
            'PYTHON_LIB_PATH': self._get_site_packages_path(),
        }
        return env

    def build(self) -> Path:
        """Build the TensorFlow wheel.

        Returns:
            Path to the built wheel file.
        """
        logger.info('=' * 60)
        logger.info('TensorFlow Wheel Builder for AMD EPYC')
        logger.info('=' * 60)
        logger.info(f'\n{self.cpu_info}')
        logger.info(f'\nTensorFlow root: {self.tf_root}')
        logger.info(f'Output directory: {self.output_dir}')
        logger.info(f'Parallel jobs: {self.jobs}')
        logger.info('=' * 60)

        # Check prerequisites
        self._check_prerequisites()

        # Create output directory
        self.output_dir.mkdir(parents=True, exist_ok=True)

        # Set up environment
        env = self._setup_environment()

        # Build the wheel
        logger.info('Starting Bazel build...')
        build_flags = self._get_bazel_build_flags()
        build_cmd = [
            'bazel', 'build',
            *build_flags,
            '//tensorflow/tools/pip_package:wheel',
        ]

        self._run_command(build_cmd, env=env)

        # Find the built wheel
        wheel_dir = self.tf_root / 'bazel-bin' / 'tensorflow' / 'tools' / 'pip_package'
        wheel_files = list(wheel_dir.glob('*.whl'))

        if not wheel_files:
            raise RuntimeError(f'No wheel files found in {wheel_dir}')

        source_wheel = wheel_files[0]
        logger.info(f'Built wheel: {source_wheel}')

        # Copy wheel to output directory
        dest_wheel = self.output_dir / source_wheel.name
        shutil.copy2(source_wheel, dest_wheel)

        # Repair the wheel for manylinux compliance
        repaired_wheel = self._repair_wheel(dest_wheel)

        logger.info('=' * 60)
        logger.info('Build completed successfully!')
        logger.info(f'Wheel location: {repaired_wheel}')
        logger.info('=' * 60)

        return repaired_wheel

    def _repair_wheel(self, wheel_path: Path) -> Path:
        """Repair the wheel for manylinux compliance.

        Args:
            wheel_path: Path to the original wheel.

        Returns:
            Path to the repaired wheel.
        """
        logger.info(f'Repairing wheel for {self.target_platform} compliance...')

        arch = platform.machine()
        plat_tag = f'{self.target_platform}_{arch}'

        repair_cmd = [
            self.python_path, '-m', 'auditwheel', 'repair',
            '--plat', plat_tag,
            '-w', str(self.output_dir),
            str(wheel_path),
        ]

        try:
            self._run_command(repair_cmd)
        except subprocess.CalledProcessError:
            logger.warning('Wheel repair failed, using original wheel')
            return wheel_path

        # Find the repaired wheel
        repaired_wheels = list(self.output_dir.glob(f'*{self.target_platform}*.whl'))
        if repaired_wheels:
            # Remove the original unrepaired wheel
            if wheel_path.exists() and wheel_path not in repaired_wheels:
                wheel_path.unlink()
            return repaired_wheels[0]

        return wheel_path


def parse_args() -> argparse.Namespace:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(
        description='Build TensorFlow wheel optimized for AMD EPYC processors',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
    # Basic build
    %(prog)s

    # Build with specific Python version
    %(prog)s --python=/usr/bin/python3.11

    # Build with custom output directory and parallelism
    %(prog)s --output-dir=/tmp/wheels --jobs=64

    # Build without OneDNN optimizations
    %(prog)s --no-onednn
        """,
    )

    parser.add_argument(
        '--python',
        dest='python_path',
        help='Path to Python interpreter (default: current Python)',
    )

    parser.add_argument(
        '--output-dir', '-o',
        dest='output_dir',
        help='Output directory for the wheel (default: ./wheel_output)',
    )

    parser.add_argument(
        '--jobs', '-j',
        type=int,
        help='Number of parallel build jobs (default: auto-detect)',
    )

    parser.add_argument(
        '--verbose', '-v',
        action='store_true',
        help='Enable verbose output',
    )

    parser.add_argument(
        '--no-onednn',
        dest='enable_onednn',
        action='store_false',
        help='Disable OneDNN (MKL-DNN) optimizations',
    )

    parser.add_argument(
        '--no-xla',
        dest='enable_xla',
        action='store_false',
        help='Disable XLA optimizations',
    )

    parser.add_argument(
        '--wheel-name',
        default='tensorflow',
        help='Name for the wheel package (default: tensorflow)',
    )

    parser.add_argument(
        '--target-platform',
        default='manylinux2014',
        choices=['manylinux2014', 'manylinux_2_17', 'linux'],
        help='Target platform for wheel repair (default: manylinux2014)',
    )

    parser.add_argument(
        '--show-cpu-info',
        action='store_true',
        help='Show CPU information and exit',
    )

    return parser.parse_args()


def main() -> int:
    """Main entry point."""
    args = parse_args()

    # Show CPU info and exit if requested
    if args.show_cpu_info:
        cpu_info = CPUInfo()
        print(cpu_info)
        print(f'\nSupported instructions:')
        for instr in ['avx', 'avx2', 'fma', 'sse4.1', 'sse4.2', 'sse4a', 'aes', 'sha']:
            supported = '✓' if cpu_info.supports_instruction(instr) else '✗'
            print(f'  {instr}: {supported}')
        return 0

    try:
        builder = TensorFlowWheelBuilder(
            python_path=args.python_path,
            output_dir=args.output_dir,
            jobs=args.jobs,
            verbose=args.verbose,
            enable_onednn=args.enable_onednn,
            enable_xla=args.enable_xla,
            wheel_name=args.wheel_name,
            target_platform=args.target_platform,
        )

        wheel_path = builder.build()
        print(f'\nWheel built successfully: {wheel_path}')
        return 0

    except Exception as e:
        logger.error(f'Build failed: {e}')
        if args.verbose:
            import traceback
            traceback.print_exc()
        return 1


if __name__ == '__main__':
    sys.exit(main())
