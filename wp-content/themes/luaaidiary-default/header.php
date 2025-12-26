<header class="site-header">
    <div class="container">
        <h1 class="site-title">
            <a href="<?php echo home_url(); ?>"><?php bloginfo('name'); ?></a>
        </h1>
        <p class="site-description"><?php bloginfo('description'); ?></p>
        
        <nav class="site-navigation">
            <?php wp_nav_menu(array('menu_class' => 'menu')); ?>
        </nav>
    </div>
</header>
