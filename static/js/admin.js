// ========================================
// ユーティリティ関数
// ========================================

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

// CSRFトークン取得
function getCSRFToken() {
    const meta = document.querySelector('meta[name="csrf-token"]');
    return meta ? meta.getAttribute('content') : '';
}

// エディタコンテンツ取得
function getEditorContent() {
    const textarea = document.querySelector('textarea[name="content"]');
    return textarea ? textarea.value : '';
}

// エディタにコンテンツ挿入
function insertIntoEditor(text) {
    const textarea = document.querySelector('textarea[name="content"]');
    if (textarea) {
        textarea.value = text;
        // プレビューも更新
        const event = new Event('input');
        textarea.dispatchEvent(event);
    }
}

// HTMLエスケープ
function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
}

// ローディング表示
function showLoading() {
    const loading = document.getElementById('ai-loading');
    if (loading) loading.style.display = 'flex';
}

function hideLoading() {
    const loading = document.getElementById('ai-loading');
    if (loading) loading.style.display = 'none';
}

// ========================================
// AI校正機能
// ========================================

// AI校正実行
async function performProofread() {
    const content = getEditorContent();
    if (!content || content.trim() === '') {
        alert('記事の内容を入力してください');
        return;
    }
    
    const tone = document.getElementById('ai-tone')?.value || 'formal';
    
    showLoading();
    
    try {
        const response = await fetch('/api/gemini/proofread', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'X-CSRF-Token': getCSRFToken()
            },
            body: JSON.stringify({
                content: content,
                tone: tone
            })
        });
        
        const result = await response.json();
        
        if (!response.ok) {
            throw new Error(result.error || '校正に失敗しました');
        }
        
        // レスポンス形式: {original, corrected, suggestions}
        showDiffModal(result.original, result.corrected, result.suggestions);
    } catch (error) {
        alert('エラー: ' + error.message);
    } finally {
        hideLoading();
    }
}

// 差分表示モーダル
function showDiffModal(original, corrected, suggestions) {
    const diffViewer = document.getElementById('diff-viewer');
    const suggestionsList = document.getElementById('suggestions-list');
    
    // 左右比較表示
    diffViewer.innerHTML = `
        <div class="diff-side-by-side">
            <div class="diff-column">
                <h4>元の本文</h4>
                <pre>${escapeHtml(original)}</pre>
            </div>
            <div class="diff-column">
                <h4>校正後の本文</h4>
                <pre>${escapeHtml(corrected)}</pre>
            </div>
        </div>
    `;
    
    // 修正提案リスト
    if (suggestions && suggestions.length > 0) {
        suggestionsList.innerHTML = '<h4>修正提案</h4>' + suggestions.map((s, i) => `
            <div class="suggestion-item">
                <input type="checkbox" id="suggestion-${i}" checked />
                <label for="suggestion-${i}">
                    <strong>${escapeHtml(s.type)}</strong>: ${escapeHtml(s.reason)}<br>
                    <span class="text-danger">- ${escapeHtml(s.original_text)}</span><br>
                    <span class="text-success">+ ${escapeHtml(s.suggested_text)}</span>
                </label>
            </div>
        `).join('');
    } else {
        suggestionsList.innerHTML = '';
    }
    
    document.getElementById('diff-modal').style.display = 'block';
    window.correctedContent = corrected;
}

// ========================================
// AI記事生成機能
// ========================================

// 記事生成結果を表示
function showArticleResult(result) {
    const preview = document.getElementById('article-preview');
    
    if (!result || !result.title) {
        preview.innerHTML = '<p class="text-danger">記事生成の結果が不正です</p>';
        return;
    }
    
    let html = `<h4>${escapeHtml(result.title)}</h4>`;
    html += '<div class="article-content-preview">';
    
    if (result.content) {
        // 改行を<br>に変換して表示
        html += escapeHtml(result.content).replace(/\n/g, '<br>');
    } else {
        html += '<p class="text-warning">記事本文が含まれていません</p>';
    }
    
    html += '</div>';
    
    if (result.meta_description) {
        html += '<div class="meta-info">';
        html += `<p><strong>メタディスクリプション:</strong> ${escapeHtml(result.meta_description)}</p>`;
        
        if (result.tags && result.tags.length > 0) {
            html += `<p><strong>推奨タグ:</strong> ${result.tags.map(t => escapeHtml(t)).join(', ')}</p>`;
        }
        
        html += '</div>';
    }
    
    preview.innerHTML = html;
    document.getElementById('article-result').style.display = 'block';
    
    window.generatedArticle = result;
}

// ========================================
// AI設定管理機能
// ========================================

// AI設定読み込み
async function loadAISettings() {
    try {
        const response = await fetch('/api/settings/ai-preferences', {
            headers: {
                'X-CSRF-Token': getCSRFToken()
            }
        });
        
        if (response.ok) {
            const data = await response.json();
            if (data.data && data.data.ai_preferences) {
                const prefs = data.data.ai_preferences;
                document.getElementById('default-tone').value = prefs.default_tone || 'formal';
                document.getElementById('default-target-audience').value = prefs.default_target_audience || '中級者';
                document.getElementById('auto-proofread').checked = prefs.auto_proofread || false;
                document.getElementById('proofread-prompt').value = prefs.proofread_prompt || '';
                document.getElementById('generate-article-prompt').value = prefs.generate_article_prompt || '';
                
                // モデル選択の読み込み（デフォルト: gemini-2.5-flash）
                const modelSelect = document.getElementById('gemini-model');
                if (modelSelect && prefs.model) {
                    modelSelect.value = prefs.model;
                }
            }
        }
    } catch (error) {
        console.error('AI設定の読み込みに失敗:', error);
    }
}

// ========================================
// DOMContentLoaded - メインイベントリスナー
// ========================================

document.addEventListener('DOMContentLoaded', function() {
    // ========================================
    // 共通機能
    // ========================================
    
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
                        'Content-Type': 'application/json',
                    },
                    body: JSON.stringify({ content: content })
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
    
    // ========================================
    // AI設定画面
    // ========================================
    if (document.getElementById('ai-settings-form')) {
        loadAISettings();
        
        // AI設定保存
        document.getElementById('ai-settings-form').addEventListener('submit', async (e) => {
            e.preventDefault();
            
            const apiKey = document.getElementById('gemini-api-key').value;
            const settings = {
                default_tone: document.getElementById('default-tone').value,
                default_target_audience: document.getElementById('default-target-audience').value,
                auto_proofread: document.getElementById('auto-proofread').checked,
                proofread_prompt: document.getElementById('proofread-prompt').value,
                generate_article_prompt: document.getElementById('generate-article-prompt').value,
                model: document.getElementById('gemini-model').value
            };
            
            try {
                // APIキー保存
                if (apiKey) {
                    const keyResponse = await fetch('/api/settings/gemini-api-key', {
                        method: 'POST',
                        headers: {
                            'Content-Type': 'application/json',
                            'X-CSRF-Token': getCSRFToken()
                        },
                        body: JSON.stringify({ api_key: apiKey })
                    });
                    
                    if (!keyResponse.ok) {
                        const error = await keyResponse.json();
                        throw new Error(error.error || 'APIキーの保存に失敗しました');
                    }
                }
                
                // AI設定保存
                const settingsResponse = await fetch('/api/settings/ai-preferences', {
                    method: 'PUT',
                    headers: {
                        'Content-Type': 'application/json',
                        'X-CSRF-Token': getCSRFToken()
                    },
                    body: JSON.stringify({
                        ai_preferences: settings
                    })
                });
                
                if (!settingsResponse.ok) {
                    const error = await settingsResponse.json();
                    throw new Error(error.error || '設定の保存に失敗しました');
                }
                
                alert('AI設定を保存しました');
                document.getElementById('gemini-api-key').value = '';
            } catch (error) {
                alert('エラー: ' + error.message);
            }
        });
        
        // API接続テスト
        const btnTestApi = document.getElementById('btn-test-api');
        if (btnTestApi) {
            btnTestApi.addEventListener('click', async () => {
                const apiKey = document.getElementById('gemini-api-key').value;
                if (!apiKey) {
                    alert('APIキーを入力してください');
                    return;
                }
                
                const resultDiv = document.getElementById('api-test-result');
                resultDiv.innerHTML = '<p>接続テスト中...</p>';
                
                try {
                    const response = await fetch('/api/gemini/test-connection', {
                        method: 'POST',
                        headers: {
                            'Content-Type': 'application/json',
                            'X-CSRF-Token': getCSRFToken()
                        },
                        body: JSON.stringify({ api_key: apiKey })
                    });
                    
                    const result = await response.json();
                    
                    if (response.ok) {
                        resultDiv.innerHTML = '<p class="text-success">✓ 接続成功！</p>';
                    } else {
                        resultDiv.innerHTML = `<p class="text-danger">✗ 接続失敗: ${escapeHtml(result.error)}</p>`;
                    }
                } catch (error) {
                    resultDiv.innerHTML = `<p class="text-danger">✗ エラー: ${escapeHtml(error.message)}</p>`;
                }
            });
        }
        
        // プロンプトをデフォルトに戻す
        const btnResetPrompts = document.getElementById('btn-reset-prompts');
        if (btnResetPrompts) {
            btnResetPrompts.addEventListener('click', () => {
                if (confirm('プロンプトをデフォルトに戻しますか？')) {
                    loadAISettings();
                }
            });
        }
        
        // モデル選択変更時の警告
        const geminiModel = document.getElementById('gemini-model');
        if (geminiModel) {
            geminiModel.addEventListener('change', (e) => {
                const selectedModel = e.target.value;
                const warningDiv = document.getElementById('model-warning');
                
                if (selectedModel.includes('pro')) {
                    // Proモデル選択時の警告
                    if (warningDiv) {
                        warningDiv.innerHTML = '<div class="alert alert-warning">⚠️ Proモデルは有料プランが推奨されます。無料プランでは利用制限がある場合があります。</div>';
                        warningDiv.style.display = 'block';
                    }
                } else {
                    // Flashモデル選択時
                    if (warningDiv) {
                        warningDiv.innerHTML = '<div class="alert alert-success">✓ 無料プランでも安心してご利用いただけます。</div>';
                        warningDiv.style.display = 'block';
                    }
                }
            });
        }
    }
    
    // ========================================
    // 記事編集画面 - AI機能
    // ========================================
    const btnProofread = document.getElementById('btn-proofread');
    const btnGenerateArticle = document.getElementById('btn-generate-article');
    
    // AI校正ボタン
    if (btnProofread) {
        btnProofread.addEventListener('click', performProofread);
    }
    
    // AI記事生成ボタン
    if (btnGenerateArticle) {
        btnGenerateArticle.addEventListener('click', () => {
            const modal = document.getElementById('article-modal');
            if (modal) {
                modal.style.display = 'block';
            }
        });
    }
    
    // AI機能が利用可能な場合のみ、残りのイベントリスナーを設定
    if (btnProofread || btnGenerateArticle) {
        
        // AI記事生成フォーム送信
        const articleForm = document.getElementById('article-form');
        if (articleForm) {
            articleForm.addEventListener('submit', async (e) => {
                e.preventDefault();
                
                const formData = new FormData(e.target);
                const params = {
                    topic: formData.get('topic'),
                    keywords: formData.get('keywords').split(',').map(k => k.trim()).filter(k => k),
                    target_audience: formData.get('target_audience'),
                    word_count: parseInt(formData.get('word_count')),
                    tone: document.getElementById('ai-tone')?.value || 'formal'
                };
                
                showLoading();
                
                try {
                    const response = await fetch('/api/gemini/generate-article', {
                        method: 'POST',
                        headers: {
                            'Content-Type': 'application/json',
                            'X-CSRF-Token': getCSRFToken()
                        },
                        body: JSON.stringify(params)
                    });
                    
                    const result = await response.json();
                    
                    if (!response.ok) {
                        throw new Error(result.error || '記事生成に失敗しました');
                    }
                    
                    // レスポンスの形式を確認: {success: true, data: {...}}
                    if (result.success && result.data) {
                        showArticleResult(result.data);
                    } else {
                        throw new Error('記事生成の結果が不正です');
                    }
                } catch (error) {
                    alert('エラー: ' + error.message);
                } finally {
                    hideLoading();
                }
            });
        }
        
        // エディタに記事を挿入
        const btnInsertArticle = document.getElementById('btn-insert-article');
        if (btnInsertArticle) {
            btnInsertArticle.addEventListener('click', () => {
                if (!window.generatedArticle) return;
                
                // タイトルをタイトルフィールドに挿入
                const titleField = document.querySelector('input[name="title"]');
                if (titleField && window.generatedArticle.title) {
                    titleField.value = window.generatedArticle.title;
                }
                
                // 記事本文をエディタに挿入
                if (window.generatedArticle.content) {
                    insertIntoEditor(window.generatedArticle.content);
                }
                
                document.getElementById('article-modal').style.display = 'none';
                alert('記事をエディタに挿入しました');
            });
        }
        
        // モーダルを閉じる
        const diffModalClose = document.getElementById('diff-modal-close');
        if (diffModalClose) {
            diffModalClose.addEventListener('click', () => {
                document.getElementById('diff-modal').style.display = 'none';
            });
        }
        
        const articleModalClose = document.getElementById('article-modal-close');
        if (articleModalClose) {
            articleModalClose.addEventListener('click', () => {
                document.getElementById('article-modal').style.display = 'none';
            });
        }
        
        const btnCancelDiff = document.getElementById('btn-cancel-diff');
        if (btnCancelDiff) {
            btnCancelDiff.addEventListener('click', () => {
                document.getElementById('diff-modal').style.display = 'none';
            });
        }
        
        // 校正結果を適用
        const btnApplyAll = document.getElementById('btn-apply-all');
        if (btnApplyAll) {
            btnApplyAll.addEventListener('click', () => {
                if (window.correctedContent) {
                    insertIntoEditor(window.correctedContent);
                    document.getElementById('diff-modal').style.display = 'none';
                    alert('校正結果を適用しました');
                }
            });
        }
    }
    
    // モーダル外クリックで閉じる
    window.addEventListener('click', (e) => {
        if (e.target.classList.contains('modal')) {
            e.target.style.display = 'none';
        }
    });
});
