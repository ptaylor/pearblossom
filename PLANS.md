PLANS.md

 Agent

    Make sure questioning is done for when planning not just implementing.


Branch to fix collections

    Make pencil icon bigger and move to be right adjusted.
    Add a trash can delete icon beside pencil (but not too close) with the same functionality as right click delete
    When creating a collection add an option for copy or use reference with the default coming from global settings.    This setting cannot be changed once set so on the edit panel show the option greyed out.   
    In a collection with images copied in make sure that is captured in the .collection.json to allow the files to be deleted.     Make sure never to delete files that are linked by reference.   This should be a strong rule for the agents - only files under the Pearblossom top-level directory that have been created by Pearblossom can be modified or deleted.
    Bug: when adding a new collection it appears twice on the collections list.
    Bug: check editing does save the name and description
    Bug: why spinning icons when reloading  thumbnails from cache?
    Add setting for size of thumbnails
    Add a refresh button on top of collections to rescan the directory 
    Change sort icon to use hierarchal dashes instead of arrows.
    UX on sort options needs improving and maybe linked with the sort icon change.






Collages branch:

    Provide similar functionality to collections for adding a new collage (unique name and optional  description).  Allow renaming and deleting (with confirmation dialog).    Collages are maintained as single JSON files in the Collages subdirectory.     Allow the same sorting, showing description , editing and deleting buttons and options as collections.
    When a collage is selected the canvas shows that collage (details to follow in separate feature)
    Images can be selected from a collection (multiple) and dragged to the canvas (details to follow in separate feature).  But if there is no Collage selected then the application prompts to create a new collage.



Collage Canvas Config feature:

    The canvas will have a tool bar (top or RHS?) that provides the following functionality  and the details are saved in the collage JSON file
        A background colour picker.   For now this just provides: pure black, pure white and maybe 6 greyscale options between black and white.   The default background color for a new collage is taken from global settings which also needs the same picker.  The default is white
        A bounding box which is used to limit the export image and uses to show what the collage will look like.
        The bounding box has two modes:
            Defined border (the default).  Here the bounding box is outside of all images with the same margin (in pixels) for all sides.   Any time an images is added to teh canvas or is moved the bounding box may change.    The default border is 40 px which can be changed in global settings.
            Manual .  When this option is selected the bounding box can only be changed by user by selecting an edge or corner and dragging.
            The bounding box is always displayed on the canvas using a dashed line in a contrasting colour to the background.



Collage Canvas image feature:

    Single images can be selected and dragged to the canvas for a collage.  When dropped they appear at the place they are dropped and are scaled visually to be approx 30% the size of the canvas.  This % can be set in global config.

    To start each image in a collage has a depth starting at 0 (the back) and incrementing.   When a new image is added it is added on top so has the next incremented depth value.

    Multiple images can be selected and dragged to the canvas for a collage.  Here the images are overlapped (down and to the right) and are all placed on top of each other when dropped (still stacked)
    Individual images can be selected and moved around the canvas.   For a defined bounding box the box changes size as images are moved. 
    When images overlap their depth is used to determine which parts are visible.

    The canvas can be zoomed in our out which should have a good UX (pinch, rollers, sliders  etc)

    There is a tool on canvas toolbar that shows the canvas sized to the bounding box, ie what will be exported.

    Any change to the canvas is saved to the underlying JSON file


Collage Canvas layering feature:

    When an image is selected it should be possible to change the layering with respect to another image.  So if the other image is below the current one then the current  one is placed just below the target one, or if it is already below then it is placed above the target image..   This needs to then adjust the depth on all images to reflect this change.  The UX on this is important to get right.

    It should be possible to rotate a selected image easily using a handle and mouse - rotation should be smooth and the image clearly display at its depth correctly and in relation to overlapping images.  The UX on this is important to get right.

    It should be possible to resize a selected image easily using a handle and mouse - rotation should be smooth and the image clearly display at its depth correctly and in relation to overlapping images.  The UX on this is important to get right but this feature is less important. that the rotation feature.


==============================================



Collage Export feature:

    A collage can be exported with the following options 
        image format - PNG or JPEG with apropiate quality settings
        image size - options to select the size based on the bounding box
        the bounding box limits what part of the canvas can be exported
        the canvas background colour must be used as the exported image background colour



Future:

    * Shadows
    * Logo - shape of a tree different colours.
    * Complex layering
    * Collage from collecion inherits its name by default.
    * Consider using hashes for file integrity with detection and repair functionality.
    * Logo
    * Auto generaete collage
    * Caching of intermediate sized images
    * Crashing deleting collage
    
    * Enhanced scaling export - slider + see resulting size
    * EXIF data
    * Images in Collage use collecion and id instead of path
    * Hanging issues
    * Performance
    * Docs for JSON
    * Help
    * Image in README
    

    


