<!DOCTYPE html>
<html <?php language_attributes(); ?>>
<head>
    <meta charset="<?php bloginfo('charset'); ?>">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title><?php wp_title(' | ', true, 'right'); ?><?php bloginfo('name'); ?></title>
    <?php wp_head(); ?>
</head>
<body <?php body_class(); ?>>

<?php get_header(); ?>

<div class="container">
    <div class="site-content">
        <main class="main-content">
            <header class="page-header">
                <h1 class="page-title">
                    <?php
                    if (is_category()) {
                        echo 'カテゴリー: ';
                        single_cat_title();
                    } elseif (is_tag()) {
                        echo 'タグ: ';
                        single_tag_title();
                    } else {
                        echo 'アーカイブ';
                    }
                    ?>
                </h1>
            </header>
            
            <?php if (have_posts()) : ?>
                <?php while (have_posts()) : the_post(); ?>
                    <article <?php post_class(); ?>>
                        <header class="entry-header">
                            <h2 class="entry-title">
                                <a href="<?php the_permalink(); ?>"><?php the_title(); ?></a>
                            </h2>
                            <div class="entry-meta">
                                投稿日: <?php the_date(); ?> | 
                                投稿者: <?php the_author(); ?>
                            </div>
                        </header>
                        
                        <div class="entry-content">
                            <?php the_excerpt(); ?>
                        </div>
                        
                        <footer class="entry-footer">
                            <?php the_category(', '); ?> | 
                            <?php the_tags('タグ: ', ', '); ?>
                        </footer>
                    </article>
                <?php endwhile; ?>
            <?php else : ?>
                <p>投稿が見つかりませんでした。</p>
            <?php endif; ?>
        </main>
        
        <?php get_sidebar(); ?>
    </div>
</div>

<?php get_footer(); ?>

</body>
</html>
