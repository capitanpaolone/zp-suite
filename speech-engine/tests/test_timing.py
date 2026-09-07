import pytest

from zp_speech.timing import contains_time


def test_intervals_are_half_open():
    assert contains_time(100, 200, 100)
    assert contains_time(100, 200, 199)
    assert not contains_time(100, 200, 200)


@pytest.mark.parametrize(("start", "end"), ((-1, 10), (10, 10), (11, 10)))
def test_invalid_intervals_are_rejected(start, end):
    with pytest.raises(ValueError, match="invalid half-open interval"):
        contains_time(start, end, start)
