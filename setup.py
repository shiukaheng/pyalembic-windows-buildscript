import glob
import shutil
import subprocess

from setuptools import find_packages, setup
from setuptools.command.install import install

import sys


class CustomInstallCommand(install):
    def run(self):
        super().run()

        # Copy all dependent binaries to the package directory
        GLOB_PATTERNS = []

        if sys.platform == "win32":
            GLOB_PATTERNS += [
                "alembic/_installed/lib/site-packages/*.pyd",
                "Imath/_installed/lib/site-packages/*.pyd",
                "boost/stage/lib/*.dll",
                "alembic/_installed/lib/*.dll",
                "Imath/_installed/bin/*.dll",
            ]
        else:   # Linux & macOS
            GLOB_PATTERNS += [
                "alembic/_installed/lib/python_site/*.so",
                "Imath/_installed/lib/*.so",
                "boost/stage/lib/*.so*",
            ]


        for pattern in GLOB_PATTERNS:
            for rel_path in glob.glob(pattern):
                print(f"file copy: '{rel_path}' -> '{self.install_lib}'")
                shutil.copy(rel_path, self.install_lib)


def get_orig_setup_py_value(name: str) -> str:
    """Retrieve a value from the setup.py file of the original Alembic project."""
    cmd = ["python", "alembic/setup.py", f"--{name}"]
    s = subprocess.run(cmd, capture_output=True, text=True).stdout
    return s.rstrip()


setup(
    name=get_orig_setup_py_value("name"),
    version=get_orig_setup_py_value("version"),
    author=get_orig_setup_py_value("author"),
    author_email=get_orig_setup_py_value("author-email"),
    description=get_orig_setup_py_value("description"),
    long_description=get_orig_setup_py_value("long-description"),
    install_requires=["numpy"],
    packages=find_packages(),
    include_package_data=True,
    cmdclass={"install": CustomInstallCommand},
    has_ext_modules=lambda: True,
)
