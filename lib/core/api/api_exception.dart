class ApiException implements Exception {
  final int code;
  final String message;

  const ApiException({required this.code, required this.message});

  @override
  String toString() => 'ApiException($code): $message';

  static String describe(int code) {
    switch (code) {
      // Common WebAPI errors
      case 100: return 'Unknown error';
      case 101: return 'Invalid parameters';
      case 102: return 'API not found';
      case 103: return 'Method not found';
      case 104: return 'API version not supported';
      case 105: return 'Permission denied';
      case 106: return 'Session timed out';
      case 107: return 'Session interrupted — duplicate login detected';
      // Auth errors
      case 400: return 'Invalid account or password';
      case 401: return 'Account disabled';
      case 402: return 'Permission denied';
      case 403: return 'Two-factor authentication required';
      case 404: return 'OTP code invalid';
      case 405: return 'OTP code required';
      case 406: return 'Account locked — too many failed attempts';
      case 407: return 'Account expired';
      case 408: return 'Password change required';
      default: return 'Error $code';
    }
  }
}
