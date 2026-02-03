<?php
$projectName = basename(dirname(__DIR__));
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title><?= htmlspecialchars($projectName) ?></title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        .container {
            background: white;
            padding: 3rem;
            border-radius: 1rem;
            box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.25);
            text-align: center;
            max-width: 500px;
        }
        h1 { color: #1a202c; margin-bottom: 1rem; }
        p { color: #718096; margin-bottom: 0.5rem; }
        .php-version { 
            background: #edf2f7; 
            padding: 0.5rem 1rem; 
            border-radius: 0.5rem; 
            display: inline-block;
            margin-top: 1rem;
            font-family: monospace;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1><?= htmlspecialchars($projectName) ?></h1>
        <p>Your project is ready!</p>
        <p class="php-version">PHP <?= PHP_VERSION ?></p>
    </div>
</body>
</html>
