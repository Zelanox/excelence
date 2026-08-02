import io
import os
import sys
from contextlib import redirect_stderr, redirect_stdout

import pytest

os.chdir('e:/ZELANOX/Excelence')

stdout_buffer = io.StringIO()
stderr_buffer = io.StringIO()

with redirect_stdout(stdout_buffer), redirect_stderr(stderr_buffer):
    exit_code = pytest.main(['-q', 'backend/tests/test_controller_spreadsheet.py'])

report = (
    f'exit_code={exit_code}\n'
    f'STDOUT:\n{stdout_buffer.getvalue()}\n'
    f'STDERR:\n{stderr_buffer.getvalue()}'
)

with open('verify_results.txt', 'w', encoding='utf-8') as handle:
    handle.write(report)

print(report)
sys.exit(exit_code)
