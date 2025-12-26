<aside class="sidebar">
    <div class="widget">
        <h3 class="widget-title">最近の投稿</h3>
        <ul>
            <?php
            // 最近の投稿を表示（簡易版）
            echo '<li><a href="#">投稿タイトル1</a></li>';
            echo '<li><a href="#">投稿タイトル2</a></li>';
            echo '<li><a href="#">投稿タイトル3</a></li>';
            ?>
        </ul>
    </div>
    
    <div class="widget">
        <h3 class="widget-title">カテゴリー</h3>
        <ul>
            <?php
            // カテゴリー一覧を表示（簡易版）
            echo '<li><a href="#">カテゴリー1</a></li>';
            echo '<li><a href="#">カテゴリー2</a></li>';
            echo '<li><a href="#">カテゴリー3</a></li>';
            ?>
        </ul>
    </div>
    
    <div class="widget">
        <h3 class="widget-title">検索</h3>
        <form method="get" action="<?php echo home_url(); ?>/search">
            <input type="text" name="s" placeholder="検索...">
            <button type="submit">検索</button>
        </form>
    </div>
</aside>
