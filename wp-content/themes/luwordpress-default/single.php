<!DOCTYPE html>
<html <?php language_attributes(); ?>>
<head>
    <meta charset="<?php bloginfo('charset'); ?>">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title><?php the_title(); ?> | <?php bloginfo('name'); ?></title>
    <?php wp_head(); ?>
</head>
<body <?php body_class(); ?>>

<?php get_header(); ?>

<div class="container">
    <div class="site-content">
        <main class="main-content">
            <?php if (have_posts()) : ?>
                <?php while (have_posts()) : the_post(); ?>
                    <article <?php post_class(); ?>>
                        <header class="entry-header">
                            <h1 class="entry-title"><?php the_title(); ?></h1>
                            <div class="entry-meta">
                                投稿日: <?php the_date(); ?> | 
                                投稿者: <?php the_author(); ?>
                            </div>
                        </header>
                        
                        <div class="entry-content">
                            <?php the_content(); ?>
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
