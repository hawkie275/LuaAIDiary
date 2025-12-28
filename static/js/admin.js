// フォーム送信時の確認
document.addEventListener('DOMContentLoaded', function() {
    // 削除ボタンの確認
    const deleteForms = document.querySelectorAll('form[action*="/delete"]');
    deleteForms.forEach(form => {
        form.addEventListener('submit', function(e) {
            if (!confirm('本当に削除しますか？この操作は取り消せません。')) {
                e.preventDefault();
            }
        });
    });
    
    // タイトルからスラッグを自動生成（カテゴリー・タグ用）
    const nameInput = document.getElementById('name');
    const slugInput = document.getElementById('slug');
    
    if (nameInput && slugInput) {
        nameInput.addEventListener('input', function() {
            if (!slugInput.value || slugInput.dataset.auto !== 'false') {
                slugInput.value = generateSlug(this.value);
                slugInput.dataset.auto = 'true';
            }
        });
        
        slugInput.addEventListener('input', function() {
            if (this.value) {
                this.dataset.auto = 'false';
            }
        });
    }
    
    // 成功メッセージの表示
    const urlParams = new URLSearchParams(window.location.search);
    if (urlParams.get('created')) {
        showNotification('投稿を作成しました', 'success');
    } else if (urlParams.get('updated')) {
        showNotification('投稿を更新しました', 'success');
    } else if (urlParams.get('deleted')) {
        showNotification('投稿を削除しました', 'success');
    }
    
    // ========================================
    // Markdownプレビュー機能
    // ========================================
    const contentTextarea = document.getElementById('content');
    const previewArea = document.getElementById('preview-area');
    
    if (contentTextarea && previewArea) {
        let debounceTimer;
        
        // プレビュー更新関数
        async function updatePreview() {
            const content = contentTextarea.value;
            
            if (!content || content.trim() === '') {
                previewArea.innerHTML = '<p class="text-muted">本文を入力するとプレビューが表示されます</p>';
                return;
            }
            
            try {
                const response = await fetch('/api/preview/markdown', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/x-www-form-urlencoded',
                    },
                    body: `content=${encodeURIComponent(content)}`
                });
                
                if (!response.ok) {
                    throw new Error('プレビューの取得に失敗しました');
                }
                
                const data = await response.json();
                previewArea.innerHTML = data.html;
            } catch (err) {
                console.error('プレビューエラー:', err);
                previewArea.innerHTML = '<p class="text-danger">プレビューの読み込みに失敗しました</p>';
            }
        }
        
        // 初回プレビュー表示
        updatePreview();
        
        // テキストエリア入力時にデバウンス付きでプレビュー更新
        contentTextarea.addEventListener('input', function() {
            clearTimeout(debounceTimer);
            debounceTimer = setTimeout(() => {
                updatePreview();
            }, 500); // 500msのデバウンス
        });
    }
});

// スラッグ生成関数（簡易版）
function generateSlug(text) {
    return text
        .toLowerCase()
        .trim()
        .replace(/[^\w\s-]/g, '')
        .replace(/[\s_-]+/g, '-')
        .replace(/^-+|-+$/g, '');
}

// 通知表示関数
function showNotification(message, type) {
    const notification = document.createElement('div');
    notification.className = `alert alert-${type}`;
    notification.textContent = message;
    notification.style.position = 'fixed';
    notification.style.top = '20px';
    notification.style.right = '20px';
    notification.style.zIndex = '9999';
    notification.style.minWidth = '300px';
    notification.style.animation = 'slideIn 0.3s ease-out';
    
    document.body.appendChild(notification);
    
    setTimeout(() => {
        notification.style.animation = 'slideOut 0.3s ease-in';
        setTimeout(() => {
            notification.remove();
        }, 300);
    }, 3000);
}
