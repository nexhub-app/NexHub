/// 规则切分器：处理 `&&`、`||`、`%%` 等复合规则分隔符与括号平衡。
library;

class RuleAnalyzer {
  final String _queue;
  int _pos = 0;
  int _start = 0;
  int _startX = 0;
  List<String> _rule = [];
  int _step = 0;
  String elementsType = '';

  /// legado `RuleAnalyzer(data, code)`：JSON/JS 风格规则用 code 平衡模式
  ///（`[`/`]` 单独记深度，转义始终生效），普通规则用 rule 模式。
  final bool code;

  RuleAnalyzer(String data, {this.code = false}) : _queue = data;

  /// 跳过起始的 `@` 与空白字符。
  void trim() {
    if (_pos < _queue.length && (_queue[_pos] == '@' || _queue.codeUnitAt(_pos) < 33)) {
      _pos++;
      while (_pos < _queue.length && (_queue[_pos] == '@' || _queue.codeUnitAt(_pos) < 33)) {
        _pos++;
      }
      _start = _pos;
      _startX = _pos;
    }
  }

  /// 重置位置到 0。
  void reSetPos() {
    _pos = 0;
    _startX = 0;
  }

  bool _consumeTo(String seq) {
    _start = _pos;
    final offset = _queue.indexOf(seq, _pos);
    if (offset != -1) {
      _pos = offset;
      return true;
    }
    return false;
  }

  bool _consumeToAny(List<String> seqs) {
    var pos = _pos;
    while (pos < _queue.length) {
      for (final s in seqs) {
        if (_queue.startsWith(s, pos)) {
          _step = s.length;
          _pos = pos;
          return true;
        }
      }
      pos++;
    }
    return false;
  }

  int _findToAny(List<String> chars) {
    var pos = _pos;
    while (pos < _queue.length) {
      for (final c in chars) {
        if (_queue.startsWith(c, pos)) return pos;
      }
      pos++;
    }
    return -1;
  }

  bool _chompRuleBalanced(String open, String close) {
    var pos = _pos;
    var depth = 0;
    var inSingleQuote = false;
    var inDoubleQuote = false;

    do {
      if (pos >= _queue.length) break;
      final c = _queue[pos++];

      if (c == "'" && !inDoubleQuote) {
        inSingleQuote = !inSingleQuote;
      } else if (c == '"' && !inSingleQuote) {
        inDoubleQuote = !inDoubleQuote;
      }

      if (inSingleQuote || inDoubleQuote) continue;

      if (c == '\\') {
        pos++;
        continue;
      }

      if (c == open) {
        depth++;
      } else if (c == close) {
        depth--;
      }
    } while (depth > 0);

    if (depth > 0) return false;
    _pos = pos;
    return true;
  }

  /// legado `chompCodeBalanced`：非内嵌代码平衡组。
  ///
  /// 与 rule 模式的区别：转义字符在引号内外都生效；`[`/`]` 单独累计一层
  /// 深度，默认括号只在 `[]` 深度归零后才参与平衡。
  bool _chompCodeBalanced(String open, String close) {
    var pos = _pos;
    var depth = 0;
    var otherDepth = 0;
    var inSingleQuote = false;
    var inDoubleQuote = false;

    do {
      if (pos >= _queue.length) break;
      final c = _queue[pos++];
      if (c != '\\') {
        if (c == "'" && !inDoubleQuote) {
          inSingleQuote = !inSingleQuote;
        } else if (c == '"' && !inSingleQuote) {
          inDoubleQuote = !inDoubleQuote;
        }

        if (inSingleQuote || inDoubleQuote) continue;

        if (c == '[') {
          depth++;
        } else if (c == ']') {
          depth--;
        } else if (depth == 0) {
          if (c == open) {
            otherDepth++;
          } else if (c == close) {
            otherDepth--;
          }
        }
      } else {
        pos++;
      }
    } while (depth > 0 || otherDepth > 0);

    if (depth > 0 || otherDepth > 0) return false;
    _pos = pos;
    return true;
  }

  bool _chompBalanced(String open, String close) =>
      code ? _chompCodeBalanced(open, close) : _chompRuleBalanced(open, close);

  /// 切分规则：支持 `&&`、`||`、`%%` 等。
  List<String> splitRule([List<String>? split]) {
    if (split == null || split.isEmpty) {
      return _splitRuleNext();
    }

    if (split.length == 1) {
      elementsType = split[0];
      if (!_consumeTo(elementsType)) {
        _rule.add(_queue.substring(_startX).trim());
        return _rule;
      }
      _step = elementsType.length;
      return splitRule();
    } else if (!_consumeToAny(split)) {
      _rule.add(_queue.substring(_startX).trim());
      return _rule;
    }

    final end = _pos;
    _pos = _start;

    do {
      final st = _findToAny(['[', '(']);
      if (st == -1) {
        _rule = [_queue.substring(_startX, end).trim()];
        elementsType = _queue.substring(end, end + _step);
        _pos = end + _step;
        while (_consumeTo(elementsType)) {
          _rule.add(_queue.substring(_start, _pos).trim());
          _pos += _step;
        }
        _rule.add(_queue.substring(_pos).trim());
        return _rule;
      }

      if (st > end) {
        _rule = [_queue.substring(_startX, end).trim()];
        elementsType = _queue.substring(end, end + _step);
        _pos = end + _step;
        while (_consumeTo(elementsType) && _pos < st) {
          _rule.add(_queue.substring(_start, _pos).trim());
          _pos += _step;
        }
        if (_pos > st) {
          _startX = _start;
          return splitRule();
        } else {
          _rule.add(_queue.substring(_pos).trim());
          return _rule;
        }
      }

      _pos = st;
      final next = _queue[_pos] == '[' ? ']' : ')';
      if (!_chompBalanced(_queue[_pos], next)) {
        throw Exception('${_queue.substring(0, _start)} 后未平衡');
      }
    } while (end > _pos);

    _start = _pos;
    return splitRule(split);
  }

  List<String> _splitRuleNext() {
    final end = _pos;
    _pos = _start;

    do {
      final st = _findToAny(['[', '(']);
      if (st == -1) {
        _rule.add(_queue.substring(_startX, end).trim());
        _pos = end + _step;
        while (_consumeTo(elementsType)) {
          _rule.add(_queue.substring(_start, _pos).trim());
          _pos += _step;
        }
        _rule.add(_queue.substring(_pos).trim());
        return _rule;
      }

      if (st > end) {
        _rule.add(_queue.substring(_startX, end).trim());
        _pos = end + _step;
        while (_consumeTo(elementsType) && _pos < st) {
          _rule.add(_queue.substring(_start, _pos).trim());
          _pos += _step;
        }
        if (_pos > st) {
          _startX = _start;
          return _splitRuleNext();
        } else {
          _rule.add(_queue.substring(_pos).trim());
          return _rule;
        }
      }

      _pos = st;
      final next = _queue[_pos] == '[' ? ']' : ')';
      if (!_chompBalanced(_queue[_pos], next)) {
        throw Exception('${_queue.substring(0, _start)} 后未平衡');
      }
    } while (end > _pos);

    _start = _pos;
    if (!_consumeTo(elementsType)) {
      _rule.add(_queue.substring(_startX).trim());
      return _rule;
    }
    return _splitRuleNext();
  }

  String innerRule(String inner, int startStep, int endStep, String? Function(String) fr) {
    final st = StringBuffer();
    while (_consumeTo(inner)) {
      final posPre = _pos;
      if (_chompCodeBalanced('{', '}')) {
        final frv = fr(_queue.substring(posPre + startStep, _pos - endStep));
        if (frv != null && frv.isNotEmpty) {
          st.write(_queue.substring(_startX, posPre) + frv);
          _startX = _pos;
          continue;
        }
      }
      _pos += inner.length;
    }
    if (_startX == 0) return '';
    st.write(_queue.substring(_startX));
    return st.toString();
  }
}
