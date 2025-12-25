<?php
/**
 * LuWordPress Default Theme Functions
 */

// テーマサポート機能を追加
function luwordpress_default_setup() {
    // タイトルタグのサポート
    add_theme_support('title-tag');
    
    // アイキャッチ画像のサポート
    add_theme_support('post-thumbnails');
    
    // HTML5サポート
    add_theme_support('html5', array(
        'search-form',
        'comment-form',
        'comment-list',
        'gallery',
        'caption',
    ));
    
    // 自動フィードリンク
    add_theme_support('automatic-feed-links');
}

// テーマのセットアップをフックに登録（Lua環境では実際には実行されない）
// add_action('after_setup_theme', 'luwordpress_default_setup');
